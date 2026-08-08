import argparse
import json
import re
from pathlib import Path


def dart_type(spec_type):
    mapping = {
        "void": "void",
        "bool": "bool",
        "int8": "int",
        "uint8": "int",
        "int16": "int",
        "uint16": "int",
        "int32": "int",
        "uint32": "int",
        "int64": "int",
        "uint64": "int",
        "float": "double",
        "double": "double",
        "funptr": "ffi.Pointer<ffi.Void>",
        "pointer": "ffi.Pointer<ffi.Void>",
        "stableptr": "ffi.Pointer<ffi.Void>",
        "cstring": "ffi.Pointer<ffi.Char>",
    }
    try:
        return mapping[spec_type]
    except KeyError as exc:
        raise SystemExit(f"unsupported Dart type in FFI spec: {spec_type}") from exc


def native_type(spec_type):
    mapping = {
        "void": "ffi.Void",
        "bool": "ffi.Int32",
        "int8": "ffi.Int8",
        "uint8": "ffi.Uint8",
        "int16": "ffi.Int16",
        "uint16": "ffi.Uint16",
        "int32": "ffi.Int32",
        "uint32": "ffi.Uint32",
        "int64": "ffi.Int64",
        "uint64": "ffi.Uint64",
        "float": "ffi.Float",
        "double": "ffi.Double",
        "funptr": "ffi.Pointer<ffi.Void>",
        "pointer": "ffi.Pointer<ffi.Void>",
        "stableptr": "ffi.Pointer<ffi.Void>",
        "cstring": "ffi.Pointer<ffi.Char>",
    }
    try:
        return mapping[spec_type]
    except KeyError as exc:
        raise SystemExit(f"unsupported native type in FFI spec: {spec_type}") from exc


def lookup_type(spec_type):
    if spec_type == "bool":
        return "int"
    return dart_type(spec_type)


def argument_expression(param):
    name = param["name"]
    if param["type"] == "bool":
        return f"{name} ? 1 : 0"
    return name


def return_expression(result, call):
    if result == "void":
        return f"    {call};"
    if result == "bool":
        return f"    return {call} != 0;"
    return f"    return {call};"


def words(identifier):
    return [word for word in re.split(r"[^0-9A-Za-z]+", identifier) if word]


def lower_camel(identifier):
    parts = words(identifier)
    if not parts:
        raise SystemExit(f"cannot build Dart identifier from: {identifier!r}")
    return parts[0][0].lower() + parts[0][1:] + "".join(
        part[:1].upper() + part[1:] for part in parts[1:]
    )


def upper_camel(identifier):
    return "".join(part[:1].upper() + part[1:] for part in words(identifier))


def render_function(function):
    name = function["name"]
    symbol = function.get("symbol", name)
    result = function.get("result", "void")
    params = function.get("params", [])

    native_params = ", ".join(native_type(param["type"]) for param in params)
    lookup_params = ", ".join(lookup_type(param["type"]) for param in params)
    wrapper_params = ", ".join(
        f"{dart_type(param['type'])} {param['name']}" for param in params
    )
    wrapper_args = ", ".join(argument_expression(param) for param in params)

    native_signature = f"{native_type(result)} Function({native_params})"
    lookup_signature = f"{lookup_type(result)} Function({lookup_params})"
    call = f"_{name}({wrapper_args})"

    return f"""
  late final _{name} = _library
      .lookupFunction<{native_signature}, {lookup_signature}>('{symbol}');

  {dart_type(result)} {name}({wrapper_params}) {{
{return_expression(result, call)}
  }}
"""


def render_storable(storable):
    name = lower_camel(storable["name"])
    method_prefix = lower_camel(storable.get("symbolPrefix", name))
    size_of_symbol = storable["sizeOfSymbol"]
    alignment_symbol = storable["alignmentSymbol"]
    fields = storable.get("fields", [])
    body = f"""
  late final _{method_prefix}SizeOf = _library
      .lookupFunction<ffi.Int32 Function(), int Function()>('{size_of_symbol}');

  late final _{method_prefix}Alignment = _library
      .lookupFunction<ffi.Int32 Function(), int Function()>('{alignment_symbol}');

  int {method_prefix}SizeOf() {{
    return _{method_prefix}SizeOf();
  }}

  int {method_prefix}Alignment() {{
    return _{method_prefix}Alignment();
  }}
"""
    body += "".join(render_storable_field(method_prefix, field) for field in fields)
    return body


def render_storable_field(method_prefix, field):
    field_suffix = upper_camel(field["name"])
    field_type = field["type"]
    getter_symbol = field["getterSymbol"]
    setter_symbol = field["setterSymbol"]
    getter_name = f"{method_prefix}Get{field_suffix}"
    setter_name = f"{method_prefix}Set{field_suffix}"
    getter_call = f"_{getter_name}(pointer)"
    setter_arg = argument_expression({"name": "value", "type": field_type})

    return f"""
  late final _{getter_name} = _library.lookupFunction<
      {native_type(field_type)} Function(ffi.Pointer<ffi.Void>),
      {lookup_type(field_type)} Function(ffi.Pointer<ffi.Void>)>('{getter_symbol}');

  late final _{setter_name} = _library.lookupFunction<
      ffi.Void Function(ffi.Pointer<ffi.Void>, {native_type(field_type)}),
      void Function(ffi.Pointer<ffi.Void>, {lookup_type(field_type)})>('{setter_symbol}');

  {dart_type(field_type)} {getter_name}(ffi.Pointer<ffi.Void> pointer) {{
{return_expression(field_type, getter_call)}
  }}

  void {setter_name}(ffi.Pointer<ffi.Void> pointer, {dart_type(field_type)} value) {{
    _{setter_name}(pointer, {setter_arg});
  }}
"""


def render(spec):
    class_name = spec.get("className", "HaskellApi")
    library_name = spec.get("libraryName", "haskell")
    runtime_init_symbol = spec.get("runtimeInitSymbol", "haskell_init")
    functions = spec.get("functions", [])
    storables = spec.get("storables", [])
    body = "".join(render_function(function) for function in functions)
    body += "".join(render_storable(storable) for storable in storables)

    return f"""// Generated from the Haskell FFI manifest.
// Do not edit manually.

import 'dart:ffi' as ffi;
import 'dart:io' as io;

class {class_name} {{
  {class_name}([String? libraryPath])
      : _library = ffi.DynamicLibrary.open(libraryPath ?? _defaultLibraryPath()) {{
    _initializeRuntime();
  }}

  static const libraryName = '{library_name}';
  static const libraryFileName = 'lib{library_name}.so';

  final ffi.DynamicLibrary _library;

  static String _defaultLibraryPath() {{
    if (io.Platform.isLinux) {{
      return '${{io.File(io.Platform.resolvedExecutable).parent.path}}/lib/$libraryFileName';
    }}
    return libraryFileName;
  }}

  late final _initializeRuntime = _library
      .lookupFunction<ffi.Void Function(), void Function()>('{runtime_init_symbol}');
{body}}}
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True, help="Path to FFI JSON spec")
    parser.add_argument("--out", required=True, help="Output Dart file")
    args = parser.parse_args()

    spec_path = Path(args.spec)
    out_path = Path(args.out)
    spec = json.loads(spec_path.read_text())
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(spec))


if __name__ == "__main__":
    main()
