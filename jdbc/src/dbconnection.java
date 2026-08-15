import java.sql.*;

public class dbconnection {
	private static final String DRIVERNAME = "oracle.jdbc.OracleDriver";
	
	private static final String URL = "jdbc:oracle:thin:@localhost:1521/FREEPDB1";
	
	private static final String USERNAME = "system";
	private static final String PASSWORD = "system";
	
	private static dbconnection instance;
    private Connection connection;


    // 1. private constructor — nobody can do: new dbconnection()
    private dbconnection() {
        try {
            // Registering Driver
            Class.forName(DRIVERNAME);

            connection = DriverManager.getConnection(URL, USERNAME, PASSWORD);
            System.out.println("connection established");
        } catch (Exception e) {
            System.out.println("connection not established!!");
            e.printStackTrace();
        }
    }
    
    // 2. only way to get the object
    public static dbconnection getInstance() {
        if (instance == null) {
            instance = new dbconnection();
        }
        return instance;
    }
    
    // 3. reuse the same Connection
    public Connection getConnection() {
        return connection;
    }
}
