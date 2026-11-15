use std::time::{Duration, Instant};

const RETRY_INTERVAL: Duration = Duration::from_secs(10);

/// Serialised by the display service, including the driver operation itself.
/// A successful plug can remain invisible while an RDP session is disconnected.
/// Keep polling for it instead of plugging another monitor on every poll.
#[derive(Default)]
pub(super) struct HeadlessRecovery {
    last_attempt: Option<Instant>,
    awaiting_display: bool,
}

impl HeadlessRecovery {
    pub(super) fn should_plug(&mut self, now: Instant, missing: bool) -> bool {
        if !missing {
            self.awaiting_display = false;
            return false;
        }
        !self.awaiting_display
            && self
                .last_attempt
                .map_or(true, |last| now.duration_since(last) >= RETRY_INTERVAL)
    }

    pub(super) fn plugged(&mut self, now: Instant, success: bool) {
        self.last_attempt = Some(now);
        self.awaiting_display = success;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn headless_startup_and_failed_driver_install_retry() {
        let mut recovery = HeadlessRecovery::default();
        let now = Instant::now();
        assert!(recovery.should_plug(now, true));
        recovery.plugged(now, false);
        assert!(!recovery.should_plug(now + Duration::from_secs(9), true));
        assert!(recovery.should_plug(now + RETRY_INTERVAL, true));
    }

    #[test]
    fn disconnected_session_does_not_accumulate_invisible_monitors() {
        let mut recovery = HeadlessRecovery::default();
        let now = Instant::now();
        assert!(recovery.should_plug(now, true));
        recovery.plugged(now, true);
        for seconds in [1, 10, 30, 300] {
            assert!(!recovery.should_plug(now + Duration::from_secs(seconds), true));
        }
        // Once the session can enumerate again, a later unplug is recoverable.
        assert!(!recovery.should_plug(now + Duration::from_secs(301), false));
        assert!(recovery.should_plug(now + Duration::from_secs(302), true));
    }

    #[test]
    fn physical_display_never_requests_a_virtual_monitor() {
        let mut recovery = HeadlessRecovery::default();
        assert!(!recovery.should_plug(Instant::now(), false));
    }
}
