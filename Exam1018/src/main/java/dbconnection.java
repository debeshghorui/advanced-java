import java.sql.*;

public class dbconnection {
	private static final String DRIVERNAME = "oracle.jdbc.OracleDriver";
	private static final String URL = "jdbc:oracle:thin:@localhost:1521/FREEPDB1";
	private static final String USERNAME = "system";
	private static final String PASSWORD = "system";

	public static Connection getConnection() {
		try {
			Class.forName(DRIVERNAME);
			Connection con = DriverManager.getConnection(URL, USERNAME, PASSWORD);
			System.out.println("connection established");
			return con;
		} catch (Exception e) {
			System.out.println("connection not established!!");
			e.printStackTrace();
			return null;
		}
	}
}
