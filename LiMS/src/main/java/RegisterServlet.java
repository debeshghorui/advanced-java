import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;

import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public class RegisterServlet extends HttpServlet {

	public void service(HttpServletRequest req, HttpServletResponse res) throws IOException {

		int bookid = Integer.parseInt(req.getParameter("bookid"));
		String title = req.getParameter("title");
		String author = req.getParameter("author");
		String publisher = req.getParameter("publisher");
		String category = req.getParameter("category");
		String edition = req.getParameter("edition");
		int year = Integer.parseInt(req.getParameter("year"));
		double price = Double.parseDouble(req.getParameter("price"));
		int quantity = Integer.parseInt(req.getParameter("quantity"));

		PrintWriter out = res.getWriter();

		try {
			Connection con = DBConnection.getConnection();
			PreparedStatement ps = con.prepareStatement(
					"insert into book values(?,?,?,?,?,?,?,?,?)");
			ps.setInt(1, bookid);
			ps.setString(2, title);
			ps.setString(3, author);
			ps.setString(4, publisher);
			ps.setString(5, category);
			ps.setString(6, edition);
			ps.setInt(7, year);
			ps.setDouble(8, price);
			ps.setInt(9, quantity);

			int result = ps.executeUpdate();

			if (result > 0) {
				out.println("Book Registered Successfully!");
			} else {
				out.println("Book Registration Failed!");
			}
			con.close();
		} catch (Exception e) {
			System.out.println(e);
			out.println("Book Registration Failed!");
		}
	}
}
