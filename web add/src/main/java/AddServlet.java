import java.io.IOException;
import java.io.PrintWriter;

import jakarta.servlet.RequestDispatcher;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

public class AddServlet extends HttpServlet {

	public void service(HttpServletRequest req, HttpServletResponse res) throws IOException, ServletException {

		int x = Integer.parseInt(req.getParameter("n1"));
		int y = Integer.parseInt(req.getParameter("n2"));
		int z = x + y;
		// System.out.println(z);

		res.setContentType("text/html");
		PrintWriter out = res.getWriter();
		out.println("Result:" + z + "<br>");

		req.setAttribute("z", z);

		// include keeps AddServlet output; forward would clear it
		RequestDispatcher rd = req.getRequestDispatcher("sq");
		rd.include(req, res);

	}

}
