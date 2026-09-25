# NOBS SQL Editor - PowerShell edition

[![Latest release](https://img.shields.io/github/v/release/monsama/nobs-sql-editor-powershell)](https://github.com/monsama/nobs-sql-editor-powershell/releases/latest)
[![test](https://github.com/monsama/nobs-sql-editor-powershell/actions/workflows/test.yml/badge.svg)](https://github.com/monsama/nobs-sql-editor-powershell/actions/workflows/test.yml)
[![compat](https://github.com/monsama/nobs-sql-editor-powershell/actions/workflows/compat.yml/badge.svg)](https://github.com/monsama/nobs-sql-editor-powershell/actions/workflows/compat.yml)
[![License: GPL v2+](https://img.shields.io/badge/license-GPL--2.0--or--later-blue)](LICENSE)

A MySQL and MariaDB client in a single PowerShell script. It starts a small web
server that listens only on 127.0.0.1, opens the interface in your browser, and runs
your queries through the `mysql` / `mysqldump` command-line tools. No installation and
no admin rights needed.

It is the same application as
[nobs-sql-editor](https://github.com/monsama/nobs-sql-editor), which ships the same
interface as a native desktop app built with [Tauri](https://tauri.app). Use this
edition on machines where you can't, or would rather not, install anything.

## At a glance

| | |
|---|---|
| **Platform** | Windows, with Windows PowerShell 5.1 or later |
| **Download** | one file, `NOBSSQL.ps1`, about 1 MB |
| **Install** | none, and no admin rights |
| **Servers** | MySQL 5.7 to 9.4 and MariaDB 10.2 to 12.3, tested - see [Supported servers](#supported-servers) |
| **Needs** | the `mysql` / `mysqldump` client tools - Settings downloads them if you have none |
| **Interface** | a Chrome or Edge app window, or your default browser |
| **Local server** | 127.0.0.1 only; its API needs a token that is new for every start |
| **Passwords** | encrypted with Windows DPAPI for your user account |
| **Your data** | `%APPDATA%\NOBSSQL` (connections, settings, query library, client tools) |
| **Network** | Only your database servers, plus what is listed under [Network access](#network-access) |
| **License** | GPL-2.0-or-later |

## Supported servers

Every change is tested against these servers, with the full live and GUI test suites:

| Server | Versions tested |
|---|---|
| MySQL | 5.7, 8.0, 8.4, 9.4 (9.4 also with `lower_case_table_names=2`) |
| MariaDB | 10.2, 10.6, 10.11, 12.3 |

Versions in between are expected to work. Older ones (MySQL 5.6, MariaDB 10.1 and before) are
not tested. Where a server lacks a feature, the app leaves it out rather than failing: there are
no roles on MySQL 5.7, and no per-account password expiry or account locking on MariaDB before
10.4, so the user editor does not offer them there.

## Running

Download `NOBSSQL.ps1` from the
[Releases](https://github.com/monsama/nobs-sql-editor-powershell/releases) page, then:

```powershell
powershell -ExecutionPolicy Bypass -File .\NOBSSQL.ps1
```

This script is not code-signed, and running it means switching the execution policy off, so it is
worth knowing you have the file that was published. Every release names its SHA-256, in the notes
and in `SHA256SUMS.txt` beside the download:

```powershell
Get-FileHash .\NOBSSQL.ps1 -Algorithm SHA256
```

[CODE_SIGNING.md](https://github.com/monsama/nobs-sql-editor/blob/main/CODE_SIGNING.md) says what
that does and does not prove: it tells you the file reached you as it was built, and nothing about
who wrote it.

If Chrome or Edge is installed, the interface opens in a window of its own, using a
separate browser profile with extensions switched off - so nothing installed in your
everyday browser reaches these fields. That matters mostly for password managers, which
otherwise offer to fill a saved credential into the box deciding which database server
you connect to. Without Chrome or Edge it falls back to your default browser, where your
extensions do apply as usual.

**Closing the console window stops the server.** Pass `-NoBrowser` to start the server
without opening a browser.

## Features

**Connections**
- Saved connection profiles with a per-connection accent colour and environment label.
- **Read-only / safe mode** for production servers: every statement is checked by the local
  server before it is sent, not only greyed out in the interface.
- SSH tunnels through the system's OpenSSH client (key, agent or password; host aliases and
  ProxyJump from `~/.ssh/config` work too).
- SSL/TLS modes up to full certificate verification.

**Editor**
- Tabbed SQL editor with syntax highlighting, and autocomplete that knows the tables and aliases
  of the statement.
- Find and replace (Ctrl+F / Ctrl+H), formatting, undo for every editor command.
- Run the whole script, the selection, or the statement at the cursor. A procedure call, or a
  script with several SELECTs, shows each result in a tab of its own.
- Explain draws the plan: every table read as a card, a full scan in red and an index lookup in
  green, with the joins, sorts and subqueries around them.
- Query history, and a reusable query library.

**Results and editing**
- Result grids with per-column filtering and sorting, column resize and show/hide, and a
  row-detail form for wide tables. Large results load as you scroll.
- Inline and full-row editing, staged as pending changes and applied in one transaction; add and
  delete rows. Right-click **Apply** (or Ctrl+Shift+S) shows the SQL it would run first.
- Pick several cells to type one value into all of them, or set them all to NULL or empty.
- **Go to referenced row** follows a foreign key, into another database too.
- Manual transactions: with Auto-commit off a tab keeps one transaction open across its runs
  until Commit or Rollback, with a log of what it has run.
- Charts: a result as bars or a line.
- Read the same rows in another character set, to tell text stored wrong from text read wrong.

**Schema**
- Browse schemas, tables, views, procedures, functions, triggers and events, with quick filtering
  and search across all schemas.
- Table designer and DDL view and edit; routines and triggers edited and recreated in place.
- ER diagrams, and table maintenance (check, analyze, optimize, repair).
- Server overview (databases, sizes, row counts, character sets) and the process list, with kill.

**Compare DB**
- Schema sync between two databases, on the same server or two different ones: columns with
  their full definitions, indexes, foreign keys and CHECK constraints. Missing tables are created
  after the tables they refer to; drops are offered but left unticked.
- Row compare: rows missing on either side and rows that differ, copied or updated by their key.

**Import and export**
- Tables or query results to CSV, INSERT statements, Excel, JSON or Markdown.
- Strict CSV import.
- Database export and import through the MySQL/MariaDB command-line tools: structure and data,
  structure only or data only, as a file per table, per database or one file.

**Users and privileges**
- Privileges as a checklist per server, database or table, with the GRANT and REVOKE shown
  before they run.
- Roles and default roles; clone an account; sign-in method, SSL, password expiry and limits.
- Who has access to a database, and a transfer script that recreates accounts and roles on
  another server.

## Keeping data exact

- **Saving grid edits:** each change is checked, inside the same transaction, to match exactly
  one row. Otherwise nothing is saved. This catches a row changed or deleted since it was loaded,
  and a TIMESTAMP key in the hour the clocks go back (it shows the same as its neighbour). FLOAT
  keys are shown rounded, so they are matched by their text.
- **Reading in another character set (read-only).** A value that reads `cafÃ©` is either stored
  wrong or being read wrong, and a grid cannot tell you which. The server transcodes text into
  the session's character set before sending it, so the box beside the connection lets you read
  the same rows in another one: UTF-8 bytes stored in a latin1 column read as mojibake in utf8mb4
  and as themselves in latin1, while data that is genuinely damaged reads badly in both. Nothing
  can be written while this is on - what is shown is not what a write would store - and the
  connection itself is opened read-only at the server, not only in the app.
- **Grid edits go to the database the query ran in**, including after a leading `USE`.
- **Compare runs both connections in UTC.** TIMESTAMP values therefore copy correctly between
  servers in different time zones, and Compare shows them in UTC.
- **Copies name their columns** (Compare, Duplicate table, INSERT exports). Invisible columns are
  included; generated columns are left out, since the server computes them. CSV exports include
  every column, and the CSV import skips generated ones.
- **INSERT exports skip rows whose key already exists** (`ON DUPLICATE KEY UPDATE`), rather than
  using `INSERT IGNORE`, which would also cut short a value that does not fit.
- **The CSV import is strict.** Header names match the table's columns ignoring case. A column
  the table does not have, or a row with more or fewer fields than the header, imports nothing.
  Foreign key and unique checks stay on, and the whole file is one transaction.
- **A per-table export is one snapshot.** The whole database is dumped once and then split into
  one file per table or view, so the files are consistent with each other even while the database
  is being written to. Two tables whose names give the same file name get two files.
- **Schema sync writes each column as the source server defines it**, including its character
  set, collation, comment and generated expression.
- **Binary values are shown and saved as `0x…` hex**, byte for byte - BLOB, BINARY, BIT, spatial
  types and MySQL 9's VECTOR.

## SSL / TLS

Each connection has an SSL mode, and optionally a CA certificate (a `.pem` file) that the two
verifying modes check the server against.

| Mode | Encrypted | Certificate checked against the CA | Host name checked |
|---|---|---|---|
| `default` | when the server offers it | – | – |
| `disabled` | no | – | – |
| `required` | yes | no | no |
| `verify-ca` | yes | yes | no ¹ |
| `verify` | yes | yes | yes |

¹ With the MySQL client. The MariaDB client - the one this app downloads - cannot check a CA
without also checking the host name, except on connections to the local machine, so with it
`verify-ca` is carried out as full `verify`. It never checks less than you asked for.

`required` and the verifying modes refuse a server without TLS rather than continue unencrypted -
also with the MariaDB client, which on its own would carry on in plaintext when it is not
verifying the certificate. Its dump tool, which cannot be given that check, is pinned to the
certificate the server presented a moment before the export. `required` checks no certificate, so it protects against eavesdropping
but not against someone posing as the server; the verifying modes do both.

**Against a MariaDB 11.4+ server, with the MariaDB client, `verify` needs no CA at all.** The
client verifies the server's certificate through the password exchange instead, and that works
for the self-signed certificate MariaDB generates for itself, remote connections included. (It is
switched off for accounts without a password.)

**Against a MySQL server using its self-signed, auto-generated certificate**, that does not
apply: you need the server's CA, and - because the certificate never names a real host - the
MySQL client with `verify-ca` (point Settings at a MySQL `mysql.exe`). The MariaDB client can only
do this for a server on the local machine.

Where to get the CA: for MySQL it is `ca.pem` in the server's data directory. MariaDB's generated
certificate has no separate CA - use the certificate itself. Either can be read off the
connection, which needs no access to the server's files:

```sh
echo | openssl s_client -starttls mysql -connect HOST:PORT -showcerts
```

The CA is the last certificate printed (for MariaDB, the only one).

**PAM and LDAP accounts** sign in through `mysql.exe` like everything else. MySQL's client sends
such a password only on an encrypted connection (`required` or a verifying mode); MariaDB's
answers PAM either way it asks. PAM sign-in in this edition is not covered by the automated tests.

## Client tools (mysql / mysqldump)

Export and Import use the official MySQL/MariaDB command-line tools, which are
**not bundled**. On first use, point the app at an existing install in
Settings, or let it download the official MariaDB client tools from
mariadb.org. The archive is checked against the SHA-256 that MariaDB's own
release API publishes for it before anything is unpacked, and a mismatch
installs nothing - the checksum comes from the API, not from the mirror the
bytes came from, so a redirected or altered download fails the check. If the
API lists no checksum, nothing is installed at all.

Auto-detection checks, in order: saved configuration, the system PATH, then
common install folders (`Program Files\MariaDB*`, `Program Files\MySQL`,
XAMPP).

**MySQL servers get MySQL's own tools** when there are any: the two optional
"MySQL servers" paths in Settings, or else the newest MySQL Server installation
(`Program Files\MySQL\MySQL Server *\bin`). That applies to everything - queries,
the grid and Compare as well as Export and Import - since this edition runs all of
it through `mysql.exe`. What a server is gets asked when you connect (with MySQL's
client too, if the default one cannot reach it) and remembered per host and port.
MariaDB servers, and MySQL servers on a machine without MySQL's tools, use the
default pair. With MySQL's client, `verify-ca` works against a MySQL server's
self-generated certificate from any address. It matters because MariaDB's
mysqldump writes values into a MySQL table's generated columns, which MySQL
refuses when the dump is restored. Without MySQL's tools such an export is
refused rather than written.

**No MySQL installed?** Settings can download MySQL's own `mysql` and `mysqldump`
(the current 8.4 LTS release from dev.mysql.com). MySQL publishes Windows binaries
only as the full server archive, so this is a ~270 MB download of which about
14 MB is kept, in `bin\mysql\`. The archive is checked against the MD5 on MySQL's
download page before anything is unpacked, and a mismatch installs nothing. If
MySQL moves its page or files, `mysql_download_page` and
`mysql_download_url_template` (with `{series}`, `{version}`, `{file_name}`) in
the config file override the defaults.

Every query goes through `mysql.exe` too, and results are read from its `--xml
--binary-as-hex` output, because XML is the only output format that tells NULL apart
from the text `'NULL'`. That needs a client with `--binary-as-hex`: the MariaDB
tools the app downloads, or MySQL 8.0.19 or later. Binary, BIT and spatial values
are shown as `0x…` hex, as in the desktop edition.

The client writes a NUL byte (`0x00`) inside a **text** column as a space. Binary
columns are not affected. Where it matters the app reads such values separately:
a table grid (a query on one table, which is what grid edits are saved from) also
asks for each text column as hex wherever it holds a NUL, so the grid shows and
saves the exact value, and Compare does the same. Should a grid not be read that
way, saving refuses a table that has any such value rather than risk matching the
wrong row. Exporting a whole table from the tree refuses such a table and points to
the Export tool, which copies bytes exactly. The result of any other query - a join,
say - still shows a NUL in text as a space, and is exported that way.

MySQL 8.4's client - the one Settings downloads - does not know MySQL 9's VECTOR type: it
prints a VECTOR's bytes as they are, with each zero byte as a space. A query on one table asks
for its VECTOR columns as hex as well and shows them exactly. In a join or an expression the
zero bytes still show as `20`. MySQL 9's own client prints VECTOR as hex itself, so with its
`mysql.exe` set for MySQL servers in Settings - or found in a MySQL 9 installation, when none is
set - every result is exact.

## Updates

A few seconds after it starts, the app asks GitHub (`api.github.com`) for the latest release of
[nobs-sql-editor-powershell](https://github.com/monsama/nobs-sql-editor-powershell/releases). If a newer version exists, a small
notice with a link appears in the bottom-left corner. Nothing is downloaded or installed.

Hide the notice with its **×** and it stays hidden until the next version. Switch the check off,
or run it by hand, under **Settings → Updates**.

## Network access

The local server listens on 127.0.0.1 only, and its API answers only requests that carry the
token of the page it opened. Apart from your database servers and SSH hosts, the app contacts:

| Host | When | What for |
|---|---|---|
| `api.github.com` | at start (can be switched off) | the update check above |
| `downloads.mariadb.org`, `dlm.mariadb.com` or a MariaDB mirror | only when you ask for it in Settings | MariaDB client tools |
| `dev.mysql.com`, `cdn.mysql.com`, `downloads.mysql.com` | only when you ask for it in Settings | MySQL client tools |

None of these requests carries anything beyond what any web request does: your IP address and a
user agent. There is no telemetry.

## How it's tested

Every push and pull request runs, on Windows:

- unit tests of the script's functions and of the interface's logic, a parse check of the whole
  file, and the checks that keep the shared interface in step with the desktop edition;
- live tests that start the script and drive its API against real MariaDB and MySQL servers,
  and GUI tests that drive the interface in a headless browser - grid edits, Compare, export and
  import, the user editor;
- the same live and GUI tests against every server in [Supported servers](#supported-servers).

They also run weekly, so a change on a vendor's download site is caught before a user meets it.
Each published release is checked afterwards: the checksums in its notes and in
`SHA256SUMS.txt` must match the files as published.

## License

Free software under the **GNU General Public License version 2** (or, at your
option, any later version). See [LICENSE](LICENSE).

Copyright (C) 2026 Viktor Ljuca - https://monsama.ch
