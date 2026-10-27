# Windows setup for Java, Eclipse, Tomcat, and Oracle 21c XE

Copy this folder onto the Windows PC, then double-click `Run-Setup.cmd`.

The script checks each program first.

- If it is missing, the script downloads it, installs it, and sets it up.
- If the installer is already in Downloads, or in `C:\dev\downloads`, that file is used.

## Command-line options

Run the script from PowerShell with optional switches to skip specific components:

```powershell
.\setup-dev-stack.ps1 -SkipJava
.\setup-dev-stack.ps1 -SkipEclipse
.\setup-dev-stack.ps1 -SkipTomcat
.\setup-dev-stack.ps1 -SkipJava -SkipEclipse -SkipTomcat
```

## What it decides

**Java.** If Java is missing, it installs the latest Temurin JDK. If the installed Java is already the latest, it leaves it. If an older Java is installed, it asks:

1. Download and install the latest
2. Continue with the Java that is already there

**Eclipse.** If Eclipse is already installed, the script uninstalls it and deletes the leftover folders and shortcuts. It then installs a fresh **Eclipse IDE for Enterprise Java and Web Developers**. That is choice 2 in the Eclipse Windows installer, the web development package.

**Tomcat.** It asks which version to install:

1. Tomcat 9
2. Tomcat 10.1
3. Latest (Tomcat 11)

If that exact version is already in `C:\dev\tomcat`, it is not downloaded again.

Tomcat is installed as a Windows service with automatic startup. It runs on port 8080 (or 8081 if 8080 is already in use). The Tomcat Manager is configured with username `admin` and password `admin`.

**Oracle Database 21c XE.** If it is already installed, it is left alone. If it is missing, the script installs it. The login id is `system` and the password is `system`.

## Notes file

Paths, ids, and passwords are saved here:

`C:\Users\<you>\Downloads\dev-setup-info.txt`

## Features

- **Resume capability**: If the setup is interrupted (closed or stopped), the next run cleans up partial downloads and unfinished installations before starting fresh.
- **Progress tracking**: Real-time progress bars show estimated time remaining for downloads and installations.
- **Intelligent caching**: The script checks Downloads, `C:\dev\downloads`, and the script folder for existing installers before downloading.
- **Checksum verification**: Downloaded files are verified against published SHA512 checksums to ensure integrity.

## Before you start

- Use 64-bit Windows 10 or Windows 11.
- Stay with the window. Oracle can take 15 to 25 minutes.
- Keep at least 12 GB free on drive C: if you want Oracle.
- For Oracle, the Windows account must be a member of Administrators.
- Oracle 21c XE does not install on Windows Home. Java, Eclipse, and Tomcat still install.
- If `ORACLE_HOME` or `TNS_ADMIN` is set, the script removes it before a new Oracle install. The Oracle installer stops when those variables exist.

## After it finishes

Open a new Command Prompt before you type `java` or `sqlplus`.

Oracle connection:

`jdbc:oracle:thin:@//127.0.0.1:1521/XEPDB1`

Tomcat 9 uses `javax.servlet`. Tomcat 10.1 and Tomcat 11 use `jakarta.servlet`.

### Tomcat control scripts

The setup creates two batch scripts in `C:\dev`:

- `Start-Tomcat.cmd` - Start Tomcat manually
- `Stop-Tomcat.cmd` - Stop Tomcat manually

These are useful if you need to restart Tomcat or if the Windows service is not running.

### Add Tomcat in Eclipse

1. Open Eclipse and pick a workspace.
2. Window, then Preferences, then Server, then Runtime Environments, then Add.
3. Choose the Tomcat version that was installed.
4. Set the directory to `C:\dev\tomcat` and choose the JDK from the notes file.
