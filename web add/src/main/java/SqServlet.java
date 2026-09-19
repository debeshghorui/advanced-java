import java.io.IOException;
import java.io.PrintWriter;

import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

public class SqServlet extends HttpServlet {

	public void service(HttpServletRequest req, HttpServletResponse res) throws IOException {

		int k = (int) req.getAttribute("z");
		k = k * k;
		res.setContentType("text/html");
		PrintWriter out = res.getWriter();
		out.println("Welcome Square :" + k);

	}

}
