import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;

import javax.servlet.RequestDispatcher;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public class DisplayServlet extends HttpServlet {

	public void service(HttpServletRequest req, HttpServletResponse res) throws IOException, ServletException {

		ArrayList<String> books = new ArrayList<String>();

		try {
			Connection con = DBConnection.getConnection();
			PreparedStatement ps = con.prepareStatement("select * from book");
			ResultSet rs = ps.executeQuery();

			while (rs.next()) {
				String row = rs.getInt("BOOK_ID") + "|" + rs.getString("BOOK_TITLE") + "|"
						+ rs.getString("AUTHOR_NAME") + "|" + rs.getString("PUBLISHER_NAME") + "|"
						+ rs.getString("CATEGORY") + "|" + rs.getString("EDITION") + "|"
						+ rs.getInt("PUBLICATION_YEAR") + "|" + rs.getDouble("PRICE") + "|"
						+ rs.getInt("QUANTITY");
				books.add(row);
			}

			con.close();
		} catch (Exception e) {
			System.out.println(e);
		}

		req.setAttribute("books", books);
		RequestDispatcher dispatcher = req.getRequestDispatcher("display.jsp");
		dispatcher.forward(req, res);
	}
}
