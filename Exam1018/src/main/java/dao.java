import java.sql.*;

public class dao {

	public static void create() {
		Connection con = dbconnection.getConnection();
		try {
			PreparedStatement ps = con.prepareStatement(
					"create table bookstore(bookid number primary key,title varchar2(20),author varchar2(20),price number,quantity number)");
			int result = ps.executeUpdate();
			System.out.println(result);
		} catch (Exception e) {
			System.out.println(e);
		}
	}

	public static boolean add(int bookid, String title, String author, int price, int quantity) {
		Connection con = dbconnection.getConnection();
		try {
			PreparedStatement ps = con.prepareStatement("insert into bookstore values(?,?,?,?,?)");
			ps.setInt(1, bookid);
			ps.setString(2, title);
			ps.setString(3, author);
			ps.setInt(4, price);
			ps.setInt(5, quantity);
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
