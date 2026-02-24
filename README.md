# HLASM Strong Type Toolkit

Strong type checking for IBM High Level Assembler. A VS Code extension backed by a native OCaml language server, because HLASM deserves better tooling than a 3270 terminal and good intentions.

Registers have types. Your assembler doesn't know that. This extension does.

## What It Does

Declare your registers with `EQUREG`, and the language server will tell you, in real time, when you're putting a float register into `LA` or a general purpose register into `LE`. It also gives you hover docs for 270+ macros, go-to-definition for labels and macro source files, find-all-references, code completion, and a tree view sidebar so you can actually browse the Bixoft macro library without grepping through `.mac` files like it's 1987.

### Features

- **Strong type checking** - `EQUREG R3,F` then use it in `LA`? That's a warning. You're welcome.
- **Hover documentation** - instructions, macros, registers, and 120+ z/OS control block fields (DCB, TCB, ASCB, CVT, the lot)
- **Go-to-definition** - labels, `EQUREG` declarations, and macro source files
- **Find all references** - every use of a label or register across the document
- **Code completion** - all HLASM instructions, 270+ Bixoft macros, registers, and labels
- **Diagnostics** - real-time type mismatch and odd float register warnings
- **Macro browser** - tree view sidebar organized by category
- **Snippets** - `IF`/`ELSE`/`ENDIF`, `DO` loops, `CASE`, `PGM` skeletons, and more

## Installation

### From the VS Code Marketplace

```
ext install hlasm-tooling.hlasm-strong-type
```

Platform-specific binaries (Windows x64, Linux x64, macOS x64/ARM64) are bundled automatically.

### From source

Requires OCaml 5.1+, opam, Node.js 18+.

```bash
# Build the language server
opam install . --deps-only
opam exec -- dune build

# Build the VS Code extension
cd vscode
npm ci
npm run compile

# Package for local install
mkdir -p server data
cp ../_build/default/bin/main.exe server/hlasm-lsp.exe   # Windows
cp ../data/macros.json data/macros.json
cp ../README.md README.md
npx @vscode/vsce package
```

Then install the `.vsix` via **Extensions > Install from VSIX**.

## Supported file types

`.asm`, `.mac`, `.mlc`, `.bal`, `.hlasm`

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `hlasm.enableTypeChecking` | `true` | Enable strong type checking for registers |
| `hlasm.macroLibraries` | `[]` | Additional macro library paths for go-to-definition |
| `hlasm.showControlBlockHints` | `true` | Show control block field hints on hover |
| `hlasm.serverPath` | `""` | Path to hlasm-lsp binary (auto-detected if empty) |

## Macro database

The extension ships with 270+ macros from the [Bixoft eXtended Assembly Language](http://www.bixoft.nl/english/bxa.htm) library, sourced from the [CBT Tape](http://www.cbttape.org/). These include:

- **Structured programming**: `IF`/`ELSE`/`ENDIF`, `DO`/`ENDDO`, `CASE`/`WHEN`/`ENDCASE`
- **Type checking**: `EQUREG`, `CHKREG`, `CHKNUM`, `CHKLIT`
- **Control block mappings**: 120+ `MAP` macros for z/OS control blocks with full field-level documentation
- **Program structure**: `PGM`, `BEGSR`/`ENDSR`/`EXSR`

To regenerate the macro database from source `.mac` files:

```bash
node src/tools/parse-macros.js
```

## Why

There's decades of brilliant work sitting on the CBT Tape that deserves a fresh coat of paint. The Bixoft macro library is genuinely excellent stuff and Abe Kornelis has been maintaining it for years, but discovering and using it shouldn't require reading raw `.mac` files in a terminal.

I also write HLASM myself and trying to build a database in assembler is already painful enough without the tooling actively working against you. If the macros have had structured programming since the 1980s, the editor should at least know what a float register is.

## Credits

- **[Abe Kornelis](http://www.bixoft.nl/)** - Bixoft eXtended Assembly Language. The macro library that makes this extension worth installing.
- **[CBT Tape](http://www.cbttape.org/)** - Where mainframe open source has lived since 1975. If you know, you know.
- **[ocaml-lsp](https://github.com/ocaml/ocaml-lsp)** - Protocol types for the language server.

## License

GPL v2 or later. See [LICENSE](LICENSE).

The Bixoft macro library is distributed under its own terms - see the `$README.mac` and `$DOC.mac` files in `resources/bixoft-macros/`.
