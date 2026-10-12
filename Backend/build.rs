use std::{env, fs, path::PathBuf};

fn main() {
    // This build dependency ensures upstream protobuf generation precedes this bridge.
    let _ = anki_proto::backend::BackendInit::default();
    let descriptors = anki_proto_gen::descriptors_path();
    println!("cargo:rerun-if-changed={}", descriptors.display());
    let bytes = fs::read(&descriptors).expect("upstream protobuf descriptors");
    let pool = prost_reflect::DescriptorPool::decode(bytes.as_slice()).unwrap();
    let (_, services) = anki_proto_gen::get_services(&pool);
    let mut code = String::from("fn rpc_metadata(name: &str) -> Option<RpcMetadata> { match name {\n");
    for service in services {
        for method in service.all_methods() {
            let name = format!("{}.{}", method.proto.parent_service().parent_file().package_name(), method.proto.name());
            code.push_str(&format!(
                "{name:?} => Some(RpcMetadata {{ service: {}, method: {}, input: {:?}, output: {:?} }}),\n",
                service.index, method.index, method.proto.input().full_name(), method.proto.output().full_name()
            ));
        }
    }
    code.push_str("_ => None, } }\n");
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    fs::write(output.join("rpc_metadata.rs"), code).unwrap();
    fs::write(output.join("descriptors.bin"), bytes).unwrap();
}
