import java.io.IOException;
import java.io.PrintWriter;

import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public class BookServlet extends HttpServlet {

	public void service(HttpServletRequest req, HttpServletResponse res) throws IOException {

		int bookid = Integer.parseInt(req.getParameter("bookid"));
		String title = req.getParameter("title");
		String author = req.getParameter("author");
		int price = Integer.parseInt(req.getParameter("price"));
		int quantity = Integer.parseInt(req.getParameter("quantity"));
		PrintWriter out = res.getWriter();

		dao.create();
		if (dao.add(bookid, title, author, price, quantity)) {
			out.println("insertion successfull");
		} else {
			out.println("insertion unsuccessfull");
		}
	}
}
