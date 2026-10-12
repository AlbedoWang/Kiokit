//! Apple platform transport for Anki's unmodified upstream backend.
//! This module only marshals JSON/protobuf and owns FFI memory. Domain operations,
//! validation, persistence, and scheduling are implemented by ankitects/anki.

use std::{ffi::{c_char, CStr}, panic::{catch_unwind, AssertUnwindSafe}, ptr, slice, sync::LazyLock};
use anki::backend::{init_backend, Backend};
use base64::{engine::general_purpose::STANDARD, Engine};
use prost::Message;
use prost_reflect::{DescriptorPool, DynamicMessage};
use serde::de::IntoDeserializer;
use serde_json::{json, Value};

static DESCRIPTORS: LazyLock<DescriptorPool> = LazyLock::new(|| {
    DescriptorPool::decode(include_bytes!(concat!(env!("OUT_DIR"), "/descriptors.bin")).as_slice()).unwrap()
});

struct RpcMetadata { service: u32, method: u32, input: &'static str, output: &'static str }
include!(concat!(env!("OUT_DIR"), "/rpc_metadata.rs"));

fn encode_message(name: &str, input: Value) -> Result<Vec<u8>, String> {
    let descriptor = DESCRIPTORS.get_message_by_name(name).ok_or_else(|| format!("Unknown protobuf type: {name}"))?;
    DynamicMessage::deserialize(descriptor, input.into_deserializer())
        .map(|message| message.encode_to_vec()).map_err(|error| error.to_string())
}

fn decode_message(name: &str, bytes: &[u8]) -> Result<Value, String> {
    let descriptor = DESCRIPTORS.get_message_by_name(name).ok_or_else(|| format!("Unknown protobuf type: {name}"))?;
    let message = DynamicMessage::decode(descriptor, bytes).map_err(|error| error.to_string())?;
    serde_json::to_value(message).map_err(|error| error.to_string())
}

fn call(backend: &Backend, name: &str, input: Value) -> Result<Value, Value> {
    // WebKit bindings for the upstream frontend protobuf transport. Encoding
    // and decoding use Anki's descriptors, including FrontendService messages.
    if name == "anki.transport.EncodeMessage" {
        let message_type = input["type"].as_str().ok_or_else(|| json!({"message": "Missing protobuf type"}))?;
        let bytes = encode_message(message_type, input["value"].clone()).map_err(|error| json!({"message": error}))?;
        return Ok(json!({"data": STANDARD.encode(bytes)}));
    }
    if name == "anki.transport.DecodeMessage" {
        let message_type = input["type"].as_str().ok_or_else(|| json!({"message": "Missing protobuf type"}))?;
        let encoded = input["data"].as_str().ok_or_else(|| json!({"message": "Missing protobuf bytes"}))?;
        let bytes = STANDARD.decode(encoded).map_err(|error| json!({"message": error.to_string()}))?;
        return decode_message(message_type, &bytes).map_err(|error| json!({"message": error}));
    }
    // This is the same upstream database transport used by Anki's Python bridge.
    // Application operations use the named RPCs; the database transport is needed
    // for legacy-format migration and read-only display projections.
    if name == "anki.db" {
        let bytes = serde_json::to_vec(&input).map_err(|error| json!({"message": error.to_string()}))?;
        return match backend.run_db_command_bytes(&bytes) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(|error| json!({"message": error.to_string()})),
            Err(bytes) => Err(decode_message("anki.backend.BackendError", &bytes).unwrap_or_else(|error| json!({"message": error}))),
        };
    }
    let metadata = rpc_metadata(name).ok_or_else(|| json!({"message": format!("Unknown upstream RPC: {name}")}))?;
    let input = encode_message(metadata.input, input).map_err(|error| json!({"message": error}))?;
    match backend.run_service_method(metadata.service, metadata.method, &input) {
        Ok(bytes) => decode_message(metadata.output, &bytes).map_err(|error| json!({"message": error})),
        Err(bytes) => Err(decode_message("anki.backend.BackendError", &bytes).unwrap_or_else(|error| json!({"message": error}))),
    }
}

unsafe fn input_bytes<'a>(data: *const u8, length: usize) -> &'a [u8] {
    if length == 0 { &[] } else { slice::from_raw_parts(data, length) }
}

unsafe fn output(value: Value, data: *mut *mut u8, length: *mut usize) {
    let buffer = serde_json::to_vec(&value).unwrap().into_boxed_slice();
    *length = buffer.len();
    *data = Box::into_raw(buffer) as *mut u8;
}

/// Initializes a backend; the caller serializes access and destroys the returned handle.
#[no_mangle]
pub unsafe extern "C" fn openanki_backend_create(data: *const u8, length: usize) -> *mut Backend {
    catch_unwind(|| {
        let input: Value = serde_json::from_slice(input_bytes(data, length)).ok()?;
        let bytes = encode_message("anki.backend.BackendInit", input).ok()?;
        init_backend(&bytes).ok().map(|backend| Box::into_raw(Box::new(backend)))
    }).ok().flatten().unwrap_or(ptr::null_mut())
}

/// Calls the named upstream RPC; outputs a JSON envelope containing value or error.
#[no_mangle]
pub unsafe extern "C" fn openanki_backend_call(backend: *mut Backend, name: *const c_char,
    data: *const u8, length: usize, response: *mut *mut u8, response_length: *mut usize) {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if backend.is_null() || name.is_null() { return json!({"error": {"message": "Invalid backend handle"}}); }
        let name = match CStr::from_ptr(name).to_str() { Ok(name) => name, Err(_) => return json!({"error": {"message": "Invalid RPC name"}}) };
        let input = match serde_json::from_slice(input_bytes(data, length)) { Ok(input) => input, Err(error) => return json!({"error": {"message": error.to_string()}}) };
        match call(&*backend, name, input) {
            Ok(value) => json!({"value": value}),
            Err(error) => json!({"error": error}),
        }
    }));
    output(result.unwrap_or_else(|_| json!({"error": {"message": "Anki backend panic"}})), response, response_length);
}

#[no_mangle]
pub unsafe extern "C" fn openanki_backend_free(data: *mut u8, length: usize) {
    if !data.is_null() { drop(Box::from_raw(ptr::slice_from_raw_parts_mut(data, length))); }
}

#[no_mangle]
pub unsafe extern "C" fn openanki_backend_destroy(backend: *mut Backend) {
    if !backend.is_null() { drop(Box::from_raw(backend)); }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_is_generated_from_upstream_services() {
        for name in ["anki.collection.OpenCollection", "anki.scheduler.GetQueuedCards", "anki.scheduler.AnswerCard", "anki.import_export.ImportAnkiPackage", "anki.card_rendering.RenderExistingCard"] {
            assert!(rpc_metadata(name).is_some(), "{name}");
        }
    }

    #[test]
    fn bridge_preserves_64_bit_ids_and_oneofs() {
        let input = json!({"cardId": "9223372036854775806", "rating": "GOOD", "currentState": {"normal": {"new": {"position": 42}}}});
        let bytes = encode_message("anki.scheduler.CardAnswer", input).unwrap();
        let output = decode_message("anki.scheduler.CardAnswer", &bytes).unwrap();
        assert_eq!(output["cardId"], "9223372036854775806");
        assert_eq!(output["currentState"]["normal"]["new"]["position"], 42);
    }

    #[test]
    fn frontend_protobufs_preserve_custom_scheduling_states() {
        let request = json!({"key": "18446744073709551615", "states": {"good": {"customData": "{\"count\":42}", "normal": {"learning": {"scheduledSecs": 600}}}}});
        let bytes = encode_message("anki.frontend.SetSchedulingStatesRequest", request.clone()).unwrap();
        assert_eq!(decode_message("anki.frontend.SetSchedulingStatesRequest", &bytes).unwrap(), request);
        let response = json!({"states": request["states"], "context": {"seed": "18446744073709551615"}});
        let bytes = encode_message("anki.frontend.SchedulingStatesWithContext", response.clone()).unwrap();
        assert_eq!(decode_message("anki.frontend.SchedulingStatesWithContext", &bytes).unwrap(), response);
    }
}
