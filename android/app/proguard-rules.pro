# Project-specific R8 rules. Every plugin we depend on (flutter_secure_storage, path_provider, the Spark SDK's
# flutter_rust_bridge glue, qr_flutter, pointycastle...) ships its own consumer-rules.pro inside its AAR, which R8
# applies automatically: this file only covers what is specific to this app module.

# flutter_rust_bridge calls into the native library by FFI (dart:ffi / JNI function lookup by name), not by Java
# reflection, so the generated binding classes do not need a keep rule. If a future SDK bump adds reflection-based
# dispatch and a release build crashes with NoSuchMethodError only after enabling minification, that is the symptom
# to search for; start by diffing against a non-minified build of the same commit.
