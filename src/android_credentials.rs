//! Android's application-scoped credential store; no screen-sharing service is required.
use hbb_common::{anyhow::anyhow, ResultType};
use jni::{
    objects::{GlobalRef, JClass, JObject, JString, JValue},
    JNIEnv, JavaVM,
};
use std::sync::OnceLock;

struct Store {
    vm: JavaVM,
    object: GlobalRef,
}

static STORE: OnceLock<Store> = OnceLock::new();

#[no_mangle]
pub extern "system" fn Java_ffi_FFI_initLanCredentialStore(
    env: JNIEnv,
    _class: JClass,
    store: JObject,
) {
    let result = (|| -> jni::errors::Result<()> {
        let vm = env.get_java_vm()?;
        let object = env.new_global_ref(store)?;
        // Activity recreation retains the application-scoped store already registered.
        STORE.get_or_init(|| Store { vm, object });
        Ok(())
    })();
    if let Err(err) = result {
        hbb_common::log::error!("Failed to initialize Android credential store: {err}");
    }
}

fn with_store<T>(
    f: impl FnOnce(&mut JNIEnv, &GlobalRef) -> jni::errors::Result<T>,
) -> ResultType<T> {
    let store = STORE
        .get()
        .ok_or_else(|| anyhow!("Android credential store is not initialized"))?;
    let mut env = store.vm.attach_current_thread()?;
    let result = env.with_local_frame(16, |env| f(env, &store.object));
    // A failed Java operation must not poison subsequent JNI calls on this worker.
    if env.exception_check()? {
        env.exception_clear()?;
    }
    result.map_err(|err| anyhow!("Android credential store operation failed: {err}"))
}

pub fn load(fingerprint: &str) -> ResultType<Option<(String, Vec<u8>)>> {
    let json = with_store(|env, store| {
        let fingerprint = env.new_string(fingerprint)?;
        let value = env
            .call_method(
                store,
                "load",
                "(Ljava/lang/String;)Ljava/lang/String;",
                &[JValue::Object(&fingerprint)],
            )?
            .l()?;
        if value.is_null() {
            return Ok(None);
        }
        let json = env.get_string(&JString::from(value))?.into();
        Ok(Some(json))
    })?;
    let Some(json): Option<String> = json else {
        return Ok(None);
    };
    let json = zeroize::Zeroizing::new(json);
    #[derive(serde::Deserialize)]
    struct Credential {
        username: String,
        password: String,
    }
    let credential: Credential = serde_json::from_str(&json)?;
    let password = zeroize::Zeroizing::new(credential.password.into_bytes());
    hbb_common::lan::validate_username(&credential.username)?;
    hbb_common::lan::validate_password(&password)?;
    Ok(Some((credential.username, password.to_vec())))
}

pub fn save(fingerprint: &str, username: &str, password: &str) -> ResultType<()> {
    with_store(|env, store| {
        let fingerprint = env.new_string(fingerprint)?;
        let username = env.new_string(username)?;
        let password = env.new_string(password)?;
        env.call_method(
            store,
            "save",
            "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
            &[
                JValue::Object(&fingerprint),
                JValue::Object(&username),
                JValue::Object(&password),
            ],
        )?;
        Ok(())
    })
}

pub fn delete(fingerprint: &str) -> ResultType<()> {
    with_store(|env, store| {
        let fingerprint = env.new_string(fingerprint)?;
        env.call_method(
            store,
            "delete",
            "(Ljava/lang/String;)V",
            &[JValue::Object(&fingerprint)],
        )?;
        Ok(())
    })
}
