import java.io.IOException;
import java.io.PrintWriter;

import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public class LoginServlet extends HttpServlet {

	public void service(HttpServletRequest req, HttpServletResponse res) throws IOException {

		String u = req.getParameter("uid");
		String p = req.getParameter("pwd");
		PrintWriter out = res.getWriter();

		dao.create();
		if (dao.add(u, p)) {
			out.println("insertion successfull");
		} else {
			out.println("insertion unsuccessfull");
		}
	}
}
