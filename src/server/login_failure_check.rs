use crate::AlarmAuditType;
use hbb_common::get_time;
#[cfg(target_os = "windows")]
use hbb_common::tokio::sync::{Mutex as TokioMutex, OwnedMutexGuard};
use hbb_common::tokio::sync::{OwnedSemaphorePermit, Semaphore};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

const OS_CREDENTIAL_LOGIN_TOTAL_IDLE_RESET_MS: i64 = 120 * 60 * 1_000;
const OS_CREDENTIAL_LOGIN_BACKOFF_BASE_SECONDS: i64 = 15;
const OS_CREDENTIAL_LOGIN_BACKOFF_MAX_SECONDS: i64 = 30 * 60;
const LAN_AUTH_BACKOFF_MAX_SECONDS: u32 = 60;
const LAN_AUTH_BACKOFF_IDLE_RESET_MS: i64 = 15 * 60 * 1_000;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub(crate) enum FailureScope {
    Default,
    TerminalOsLogin,
}

pub(crate) struct OsCredentialPolicyDecision {
    pub allowed: bool,
    pub login_error: Option<String>,
    pub audit: Option<AlarmAuditType>,
}

#[derive(Copy, Clone, Debug, Default)]
struct OsCredentialFailureState {
    total_failures: i32,
    backoff_until_ms: Option<i64>,
    last_failure_ms: Option<i64>,
}

#[derive(Copy, Clone, Debug, Default)]
struct LanAuthFailureState {
    failures: u32,
    retry_until_ms: i64,
    last_failure_ms: i64,
}

lazy_static::lazy_static! {
    static ref OS_CREDENTIAL_LOGIN_FAILURE_STATE: Mutex<OsCredentialFailureState> =
        Mutex::new(OsCredentialFailureState::default());
}

lazy_static::lazy_static! {
    static ref LAN_AUTH_GATE: Arc<Semaphore> = Arc::new(Semaphore::new(2));
    static ref LAN_AUTH_FAILURES: Mutex<HashMap<String, LanAuthFailureState>> =
        Mutex::new(HashMap::new());
}

pub(crate) fn try_acquire_lan_auth_gate() -> Result<OwnedSemaphorePermit, ()> {
    LAN_AUTH_GATE.clone().try_acquire_owned().map_err(|_| ())
}

pub(crate) fn lan_auth_retry_after(keys: &[String]) -> u32 {
    lan_auth_retry_after_at(keys, get_time())
}

fn lan_auth_retry_after_at(keys: &[String], now_ms: i64) -> u32 {
    let mut failures = LAN_AUTH_FAILURES.lock().unwrap();
    failures.retain(|_, state| {
        now_ms.saturating_sub(state.last_failure_ms) < LAN_AUTH_BACKOFF_IDLE_RESET_MS
    });
    keys.iter()
        .filter_map(|key| failures.get(key))
        .map(|state| {
            let remaining_ms = state.retry_until_ms.saturating_sub(now_ms);
            ((remaining_ms + 999) / 1_000).max(0) as u32
        })
        .max()
        .unwrap_or(0)
}

pub(crate) fn record_lan_auth_failure(keys: &[String]) -> u32 {
    record_lan_auth_failure_at(keys, get_time())
}

fn record_lan_auth_failure_at(keys: &[String], now_ms: i64) -> u32 {
    let mut failures = LAN_AUTH_FAILURES.lock().unwrap();
    let mut retry_after = 0;
    for key in keys {
        let state = failures.entry(key.clone()).or_default();
        if now_ms.saturating_sub(state.last_failure_ms) >= LAN_AUTH_BACKOFF_IDLE_RESET_MS {
            *state = LanAuthFailureState::default();
        }
        state.failures = state.failures.saturating_add(1);
        state.last_failure_ms = now_ms;
        let delay = if state.failures < 2 {
            0
        } else {
            1_u32
                .checked_shl((state.failures - 2).min(6))
                .unwrap_or(LAN_AUTH_BACKOFF_MAX_SECONDS)
                .min(LAN_AUTH_BACKOFF_MAX_SECONDS)
        };
        state.retry_until_ms = now_ms.saturating_add(i64::from(delay) * 1_000);
        retry_after = retry_after.max(delay);
    }
    retry_after
}

pub(crate) fn clear_lan_auth_source(source_ip: &str) {
    LAN_AUTH_FAILURES.lock().unwrap().remove(source_ip);
}

#[cfg(target_os = "windows")]
lazy_static::lazy_static! {
    static ref OS_CREDENTIAL_LOGIN_MUTEX: Arc<TokioMutex<()>> = Arc::new(TokioMutex::new(()));
}

fn is_os_credential_scope(scope: FailureScope) -> bool {
    matches!(scope, FailureScope::TerminalOsLogin)
}

fn state_for_os_credential_scope(
    scope: FailureScope,
) -> Option<&'static Mutex<OsCredentialFailureState>> {
    if is_os_credential_scope(scope) {
        Some(&OS_CREDENTIAL_LOGIN_FAILURE_STATE)
    } else {
        None
    }
}

fn backoff_audit_type_for_scope(scope: FailureScope) -> Option<AlarmAuditType> {
    match scope {
        FailureScope::TerminalOsLogin => Some(AlarmAuditType::TerminalOsLoginBackoff),
        FailureScope::Default => None,
    }
}

fn os_credential_login_backoff_seconds(total_failures: i32) -> i64 {
    if total_failures <= 2 {
        return 0;
    }
    let exp = (total_failures - 3).min(7);
    let seconds = OS_CREDENTIAL_LOGIN_BACKOFF_BASE_SECONDS * (1_i64 << exp);
    seconds.min(OS_CREDENTIAL_LOGIN_BACKOFF_MAX_SECONDS)
}

fn normalize_backoff(state: &mut OsCredentialFailureState, now_ms: i64) {
    if let Some(until_ms) = state.backoff_until_ms {
        if until_ms <= now_ms {
            state.backoff_until_ms = None;
        }
    }
}

fn reset_totals_on_idle(state: &mut OsCredentialFailureState, now_ms: i64) {
    if let Some(last_ms) = state.last_failure_ms {
        if now_ms.saturating_sub(last_ms) >= OS_CREDENTIAL_LOGIN_TOTAL_IDLE_RESET_MS {
            state.total_failures = 0;
            state.backoff_until_ms = None;
            state.last_failure_ms = None;
        }
    }
}

fn allow_decision() -> OsCredentialPolicyDecision {
    OsCredentialPolicyDecision {
        allowed: true,
        login_error: None,
        audit: None,
    }
}

fn block_decision(
    login_error: String,
    alarm_type: Option<AlarmAuditType>,
) -> OsCredentialPolicyDecision {
    OsCredentialPolicyDecision {
        allowed: false,
        login_error: Some(login_error),
        audit: alarm_type,
    }
}

pub(crate) fn evaluate_os_credential_policy(
    scope: FailureScope,
    now_ms: i64,
) -> OsCredentialPolicyDecision {
    if !is_os_credential_scope(scope) {
        return allow_decision();
    }
    let Some(state_mutex) = state_for_os_credential_scope(scope) else {
        return allow_decision();
    };
    let mut state = state_mutex.lock().unwrap();
    reset_totals_on_idle(&mut state, now_ms);
    normalize_backoff(&mut state, now_ms);

    if let Some(until_ms) = state.backoff_until_ms {
        let remaining_ms = (until_ms - now_ms).max(0);
        let remaining_seconds = ((remaining_ms + 999) / 1_000).max(1);
        let seconds_label = if remaining_seconds == 1 {
            "second"
        } else {
            "seconds"
        };
        block_decision(
            format!(
                "Please try again in {} {}.",
                remaining_seconds, seconds_label
            ),
            backoff_audit_type_for_scope(scope),
        )
    } else {
        allow_decision()
    }
}

pub(crate) fn record_os_credential_failure(scope: FailureScope) {
    if !is_os_credential_scope(scope) {
        return;
    }
    let Some(state_mutex) = state_for_os_credential_scope(scope) else {
        return;
    };
    let mut state = state_mutex.lock().unwrap();
    let now_ms = get_time();
    reset_totals_on_idle(&mut state, now_ms);
    normalize_backoff(&mut state, now_ms);
    state.total_failures = state.total_failures.saturating_add(1);
    state.last_failure_ms = Some(now_ms);
    let backoff_seconds = os_credential_login_backoff_seconds(state.total_failures);
    if backoff_seconds > 0 {
        state.backoff_until_ms = Some(now_ms + backoff_seconds * 1_000);
    }
}

#[cfg(target_os = "windows")]
pub(crate) fn try_acquire_os_credential_login_gate() -> Result<OwnedMutexGuard<()>, ()> {
    OS_CREDENTIAL_LOGIN_MUTEX
        .clone()
        .try_lock_owned()
        .map_err(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_MUTEX: Mutex<()> = Mutex::new(());

    fn clear_os_credential_failure_state(scope: FailureScope) {
        if let Some(state_mutex) = state_for_os_credential_scope(scope) {
            *state_mutex.lock().unwrap() = OsCredentialFailureState::default();
        }
    }

    fn clear_lan_auth_failure_state() {
        LAN_AUTH_FAILURES.lock().unwrap().clear();
    }

    #[test]
    fn lan_auth_backoff_applies_to_every_source_key() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_lan_auth_failure_state();
        let keys = vec![
            "fd00::1234".to_owned(),
            "fd00::/64".to_owned(),
            "fd00::/56".to_owned(),
            "fd00::/48".to_owned(),
        ];
        assert_eq!(record_lan_auth_failure(&keys), 0);
        assert_eq!(record_lan_auth_failure(&keys), 1);
        assert!(lan_auth_retry_after(&keys) > 0);
        clear_lan_auth_source(&keys[0]);
        assert!(lan_auth_retry_after(&keys) > 0);
        clear_lan_auth_failure_state();
    }

    #[test]
    fn lan_auth_failures_expire_after_the_idle_window() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_lan_auth_failure_state();
        let keys = vec!["192.168.1.20".to_owned()];
        let now_ms = 1_000_000;

        assert_eq!(record_lan_auth_failure_at(&keys, now_ms), 0);
        assert_eq!(record_lan_auth_failure_at(&keys, now_ms + 1), 1);
        assert_eq!(lan_auth_retry_after_at(&keys, now_ms + 2), 1);
        assert_eq!(
            lan_auth_retry_after_at(&keys, now_ms + LAN_AUTH_BACKOFF_IDLE_RESET_MS + 2,),
            0
        );

        clear_lan_auth_failure_state();
    }

    #[test]
    fn os_credential_policy_prioritizes_backoff() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_os_credential_failure_state(FailureScope::TerminalOsLogin);
        let now_ms = get_time();
        for _ in 0..3 {
            record_os_credential_failure(FailureScope::TerminalOsLogin);
        }
        let decision = evaluate_os_credential_policy(FailureScope::TerminalOsLogin, now_ms);
        assert!(!decision.allowed);
        assert!(decision.login_error.is_some());
        clear_os_credential_failure_state(FailureScope::TerminalOsLogin);
    }

    #[test]
    fn os_credential_policy_idle_window_resets_total_counter() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_os_credential_failure_state(FailureScope::TerminalOsLogin);
        for _ in 0..13 {
            record_os_credential_failure(FailureScope::TerminalOsLogin);
        }
        let blocked = evaluate_os_credential_policy(FailureScope::TerminalOsLogin, get_time());
        assert!(!blocked.allowed);

        let after_failures_ms = get_time();
        let after_idle_ms = after_failures_ms + OS_CREDENTIAL_LOGIN_TOTAL_IDLE_RESET_MS + 1_000;
        let allowed = evaluate_os_credential_policy(FailureScope::TerminalOsLogin, after_idle_ms);
        assert!(allowed.allowed);
        clear_os_credential_failure_state(FailureScope::TerminalOsLogin);
    }

    #[test]
    fn os_credential_policy_audits_every_backoff_block() {
        let _guard = TEST_MUTEX.lock().unwrap();
        clear_os_credential_failure_state(FailureScope::TerminalOsLogin);

        for _ in 0..3 {
            record_os_credential_failure(FailureScope::TerminalOsLogin);
        }
        let now_ms = get_time();
        let first = evaluate_os_credential_policy(FailureScope::TerminalOsLogin, now_ms);
        let second = evaluate_os_credential_policy(FailureScope::TerminalOsLogin, now_ms + 1_000);
        assert!(!first.allowed);
        assert!(!second.allowed);
        assert!(first.audit.is_some());
        assert!(second.audit.is_some());

        clear_os_credential_failure_state(FailureScope::TerminalOsLogin);
    }
}
