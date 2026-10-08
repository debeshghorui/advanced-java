# Advanced Java

College lab projects for servlets, JDBC, and Oracle. Open the folders in Eclipse and run the web apps on Tomcat.

## Projects

| Folder | What it does | Servlet API |
| --- | --- | --- |
| `fistDemo` | Static page that prints “Hello from tomcat”. | Jakarta (`web.xml` 6.0) |
| `web add` | Form adds two numbers, then a second servlet squares the sum. | Jakarta |
| `jdbc` | Console menu to create, add, update, delete, and display rows in an `employee` table. | none |
| `LoginApp` | Form that inserts a user id and password. | `javax.servlet` (`web.xml` 4.0) |
| `Exam1018` | Bookstore form that inserts book id, title, author, price, and quantity. | `javax.servlet` |

`javax.servlet` needs **Tomcat 9**. Jakarta servlets need **Tomcat 10.1 or 11**.

JDBC apps connect with user `system` and password `system`:

```text
jdbc:oracle:thin:@localhost:1521/FREEPDB1
```

`LoginApp` and `Exam1018` already include `ojdbc17.jar` under `WEB-INF/lib`. The console app uses `jdbc/src/lib/ojdbc17.jar`.

## Windows setup

The `windows setup` folder installs Java, Eclipse, Tomcat, and Oracle Database 21c XE on a Windows PC.

1. Copy the `windows setup` folder onto the PC.
2. Double-click `Run-Setup.cmd`.
3. Approve the Administrator prompt and leave the window open until it finishes.

`Run-Setup.cmd` starts `setup-dev-stack.ps1`. The script checks each program first. It downloads and installs only what is missing, and it reuses an installer already sitting in Downloads or in `C:\dev\downloads`.

What it installs:

- **Java.** Latest Temurin JDK when Java is missing. If an older Java is already there, it asks whether to upgrade or keep it.
- **Eclipse.** Removes any existing Eclipse, then installs Eclipse IDE for Enterprise Java and Web Developers.
- **Tomcat.** Asks for Tomcat 9, Tomcat 10.1, or the latest (Tomcat 11). Installs into `C:\dev\tomcat`.
- **Oracle 21c XE.** Installs only when it is missing. Login id and password are both `system`.

Paths, ids, and passwords are written to `C:\Users\<you>\Downloads\dev-setup-info.txt`.

Use 64-bit Windows 10 or 11. Oracle needs about 12 GB free on `C:` and an Administrator account. It does not install on Windows Home; Java, Eclipse, and Tomcat still do. Oracle can take 15 to 25 minutes. Open a new Command Prompt before you run `java` or `sqlplus`.

Oracle 21c XE uses the service name `XEPDB1`. The Java files in this repo use `FREEPDB1` (Oracle Database Free). After the Windows Oracle install, change the URL in each `dbconnection.java` to:

```text
jdbc:oracle:thin:@localhost:1521/XEPDB1
```

Full notes, including how to add Tomcat in Eclipse, are in [`windows setup/README.md`](windows%20setup/README.md).

## Oracle with Docker

`docker-compose.yml` starts Oracle Database Free, which matches the `FREEPDB1` URL already in the Java files. Password is `system`. Ports are `1521` and `5500`.

```bash
docker compose up -d
```

The first start takes several minutes. The database is ready when the container log says the database is available.
