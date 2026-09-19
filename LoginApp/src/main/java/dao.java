import java.sql.*;

public class dao {

	public static void create() {
		Connection con = dbconnection.getConnection();
		try {
			PreparedStatement ps = con.prepareStatement(
					"create table login300(userid varchar2(10) primary key,password varchar2(10))");
			int result = ps.executeUpdate();
			System.out.println(result);
		} catch (Exception e) {
			System.out.println(e);
		}
	}

	public static boolean add(String uid, String Psw) {
		Connection con = dbconnection.getConnection();
		try {
			PreparedStatement ps = con.prepareStatement("insert into login300 values(?,?)");
			ps.setString(1, uid);
			ps.setString(2, Psw);
			int result = ps.executeUpdate();
			if (result > 0) {
				con.close();
				return true;
			}
		} catch (Exception e) {
			System.out.println(e);
		}
		return false;
	}
}
