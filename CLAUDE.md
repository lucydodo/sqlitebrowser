# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

DB Browser for SQLite (DB4S): a Qt Widgets desktop GUI for SQLite/SQLCipher databases, written in C++ and built with CMake. Detailed per-platform build instructions are in `BUILDING.md`.

## Build

```bash
mkdir build && cd build
cmake -G Ninja -DENABLE_TESTING=ON ..   # add -DQT_MAJOR=Qt6 for Qt6 (default is Qt5)
ninja
```

Key CMake options (see `config/options.cmake`):
- `QT_MAJOR` — `Qt5` (default, C++14) or `Qt6` (C++17).
- `ENABLE_TESTING` — builds the unit tests in `src/tests` (off by default).
- `sqlcipher` — link against SQLCipher instead of SQLite; defines `ENABLE_SQLCIPHER`, which gates encryption code paths.
- `customTap` — macOS: use SQLite/SQLCipher/Qt from the `sqlitebrowser/tap` Homebrew tap (`brew install sqlb-qt@5 sqlb-sqlcipher sqlb-sqlite`), as CI does.
- `BUILD_STABLE_VERSION` — off means a nightly build (adds a `BUILD_VERSION` date stamp).
- `FORCE_INTERNAL_QSCINTILLA` / `FORCE_INTERNAL_QCUSTOMPLOT` / `FORCE_INTERNAL_QHEXEDIT` — use the vendored copies under `libs/` instead of system packages (wired up in `config/3dparty.cmake`).

The source list is explicit in the root `CMakeLists.txt`: new `.cpp`/`.h`/`.ui` files must be added there (and to `src/tests/CMakeLists.txt` if a test needs them).

## Tests

Tests are standalone QtTest executables registered with CTest; each test links only the specific source files it needs (see `src/tests/CMakeLists.txt`), not the whole app.

```bash
cd build
ctest -V                     # all tests (CI runs `ninja test`)
ctest -R test-sqlobjects -V  # single test target
./src/tests/test-sqlobjects someTestFunction   # single QtTest function
```

Targets: `test-sqlobjects` (SQL parser + `sqlb` schema types), `test-import` (CSV parser), `test-regex`, `test-global-filter`, `test-cache` (`RowCache`).

## Architecture

- **`DBBrowserDB` (`src/sqlitedb.*`)** owns the single `sqlite3*` connection and the parsed schema (`schemata`). Access to the raw handle is exclusive: callers borrow it with `db.get("<user description>")`, which returns a `unique_ptr` whose deleter releases the lock. If another user holds it, the UI asks whether to interrupt the running query. Release the pointer promptly; holding it while calling something else that calls `get()` will block or pop up the "database busy" prompt. Edits are wrapped in savepoints (`setSavepoint`/`revertAll`/`releaseAllSavepoints`) so "Write Changes"/"Revert Changes" map to releasing or rolling back them.
- **Background threads:** `RunSql` (`src/RunSql.*`, executes the Execute SQL tab's statements) and `RowLoader` (`src/RowLoader.*`, fetches rows for the data grid) are `QThread`s that take the borrowed DB handle and report back via signals.
- **Data grid:** `SqliteTableModel` (`src/sqlitetablemodel.*`) is a lazy `QAbstractTableModel` backed by `RowCache` (sparse row cache) filled by `RowLoader`. Queries it runs are built from `sqlb::Query` (`src/sql/Query.*`), which holds the table, sort, filters, and selected columns. `TableBrowser`/`TableBrowserDock` host the browse view; filters, conditional formats (`CondFormat`) and display formats feed into the query/model.
- **SQL schema model (`src/sql/`, namespace `sqlb`):** `sqlitetypes.*` defines `Table`, `Field`, `Index`, `View`, `Trigger`, constraints, etc., and can regenerate SQL from them (used by `EditTableDialog` to alter tables). `ObjectIdentifier` handles schema-qualified, escaped names.
- **SQL parser (`src/sql/parser/`):** a flex/bison parser for `CREATE TABLE`/`CREATE INDEX` statements, entry point `ParserDriver`. The generated `sqlite3_lexer.cpp/.h` and `sqlite3_parser.cpp/.hpp` are committed — never edit them by hand; edit `sqlite3_lexer.ll` / `sqlite3_parser.yy` and regenerate with `flex sqlite3_lexer.ll` and `bison sqlite3_parser.yy` in that directory, committing both source and output.
- **UI:** `MainWindow` is the hub that wires docks, tabs and dialogs together. Dialogs follow the `Foo.cpp/.h/.ui` pattern compiled with AUTOUIC. The SQL editor is QScintilla-based (`ExtendedScintilla` → `SqlTextEdit`, with `SqlUiLexer` for highlighting/autocomplete).
- **Settings (`src/Settings.*`):** a fully static wrapper over `QSettings` with an in-memory cache. Every key is read through `Settings::getValue(group, name)`, and its default lives in `Settings::getDefaultValue` in `Settings.cpp` — add the default there when introducing a new setting, and expose it in `PreferencesDialog` if user-facing.
- **Loadable extensions:** `src/extensions/*.c` are SQLite extensions built separately (CI compiles them by hand), not part of the CMake target.
- **Translations:** `src/translations/sqlb_*.ts`, listed in `config/translations.cmake`. User-visible strings go through `tr()`.
- **Packaging/CI:** `installer/` (macOS notarization, WiX for Windows), `distri/`, `snap/`; CI workflows in `.github/workflows/cppcmake-*.yml`, called from `cppcmake.yml`.
