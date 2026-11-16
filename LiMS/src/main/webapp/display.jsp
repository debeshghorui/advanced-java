<%@ page import="java.util.ArrayList" %>
<%
	ArrayList<String> books = (ArrayList<String>) request.getAttribute("books");
	int bookCount = books == null ? 0 : books.size();
%>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<title>Library Management System | Book Catalogue</title>
	<style>
		:root {
			--navy: #172b3a;
			--navy-light: #24465d;
			--teal: #258f89;
			--orange: #f47738;
			--ink: #1d2933;
			--muted: #6c7b87;
			--line: #dce3e8;
			--paper: #f4f7f8;
			--white: #ffffff;
		}
		* { box-sizing: border-box; }
		body {
			margin: 0;
			font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
			color: var(--ink);
			background: radial-gradient(circle at 10% 0%, #e7f2f1 0, transparent 31rem), var(--paper);
			min-height: 100vh;
		}
		.topbar { background: var(--navy); color: var(--white); border-bottom: 4px solid var(--teal); }
		.topbar-inner {
			max-width: 1240px; margin: 0 auto; padding: 17px 24px;
			display: flex; align-items: center; justify-content: space-between; gap: 18px;
		}
		.brand { display: flex; align-items: center; gap: 12px; font-weight: 700; letter-spacing: .02em; }
		.brand-mark { width: 37px; height: 37px; display: grid; place-items: center; border-radius: 11px; background: var(--teal); color: white; font-size: 17px; }
		.brand small { display: block; margin-top: 2px; color: #b8c7d0; font-size: 10px; letter-spacing: .16em; }
		.top-link { color: #e7eef2; text-decoration: none; font-size: 13px; font-weight: 600; }
		.top-link:hover { color: #8de0d7; }
		main { max-width: 1240px; margin: 0 auto; padding: 46px 24px 64px; }
		.page-heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 22px; margin-bottom: 24px; }
		.eyebrow { color: var(--teal); font-size: 11px; font-weight: 800; letter-spacing: .17em; text-transform: uppercase; }
		h1 { margin: 9px 0 7px; color: var(--navy); font-size: clamp(28px, 4vw, 38px); line-height: 1.12; letter-spacing: -.035em; }
		.page-heading p { margin: 0; color: var(--muted); font-size: 14px; line-height: 1.5; }
		.count-badge { flex: 0 0 auto; padding: 10px 14px; border: 1px solid #cfe7e4; border-radius: 999px; background: #eaf6f4; color: #237b76; font-size: 12px; font-weight: 700; }
		.table-card { overflow: hidden; border: 1px solid #e2e8ec; border-radius: 15px; background: var(--white); box-shadow: 0 16px 42px rgba(23, 43, 58, .08); }
		.table-scroll { overflow-x: auto; }
		table { width: 100%; min-width: 980px; border-collapse: collapse; }
		thead { background: var(--navy); color: white; }
		th { padding: 15px 13px; color: #fff; font-size: 11px; font-weight: 700; letter-spacing: .035em; text-align: left; white-space: nowrap; }
		td { padding: 14px 13px; border-bottom: 1px solid #edf0f2; color: #354651; font-size: 13px; vertical-align: middle; }
		tbody tr:nth-child(even) { background: #f8fafb; }
		tbody tr:hover { background: #eef7f6; }
		tbody tr:last-child td { border-bottom: 0; }
		td:first-child { color: var(--teal); font-weight: 800; }
		.empty-state { padding: 52px 20px; color: var(--muted); text-align: center; }
		.empty-state strong { display: block; margin-bottom: 7px; color: var(--navy); font-size: 16px; }
		.empty-state span { font-size: 13px; }
		.table-footer { display: flex; align-items: center; justify-content: space-between; gap: 15px; padding: 15px 18px; border-top: 1px solid #edf0f2; color: var(--muted); font-size: 12px; }
		.back-link { display: inline-flex; align-items: center; gap: 8px; padding: 10px 14px; border-radius: 8px; background: var(--navy); color: white; font-size: 12px; font-weight: 700; text-decoration: none; transition: background .16s; }
		.back-link:hover { background: var(--teal); }
		.page-footer { margin-top: 22px; color: #8a969f; font-size: 11px; text-align: center; }
		@media (max-width: 650px) {
			.topbar-inner { padding: 14px 18px; }
			main { padding: 32px 15px 42px; }
			.page-heading { align-items: flex-start; flex-direction: column; }
			.table-footer { align-items: flex-start; flex-direction: column; }
		}
	</style>
</head>
<body>
	<header class="topbar">
		<div class="topbar-inner">
			<div class="brand">
				<div class="brand-mark" aria-hidden="true">L</div>
				<div>Library Management System<small>BOOK COLLECTION</small></div>
			</div>
			<a class="top-link" href="index.html">Register a book&nbsp; →</a>
		</div>
	</header>

	<main>
		<section class="page-heading" aria-labelledby="page-title">
			<div>
				<div class="eyebrow">Library catalogue</div>
				<h1 id="page-title">Registered books</h1>
				<p>Browse the books currently saved in the library collection.</p>
			</div>
			<div class="count-badge"><%= bookCount %> <%= bookCount == 1 ? "book" : "books" %></div>
		</section>

		<section class="table-card" aria-label="Book records">
			<div class="table-scroll">
				<table>
					<thead>
						<tr>
							<th scope="col">Book ID</th>
							<th scope="col">Book title</th>
							<th scope="col">Author</th>
							<th scope="col">Publisher</th>
							<th scope="col">Category</th>
							<th scope="col">Edition</th>
							<th scope="col">Publication year</th>
							<th scope="col">Price</th>
							<th scope="col">Quantity</th>
						</tr>
					</thead>
					<tbody>
						<% if (books != null && !books.isEmpty()) { %>
							<% for (String row : books) {
								String[] cols = row.split("\\|"); %>
								<tr>
									<% for (String col : cols) { %>
										<td><%= col %></td>
									<% } %>
								</tr>
							<% } %>
						<% } else { %>
							<tr>
								<td colspan="9">
									<div class="empty-state">
										<strong>No books registered yet</strong>
										<span>Use the registration form to add the first book to the collection.</span>
									</div>
								</td>
							</tr>
						<% } %>
					</tbody>
				</table>
			</div>
			<div class="table-footer">
				<span>Showing <%= bookCount %> <%= bookCount == 1 ? "record" : "records" %></span>
				<a class="back-link" href="index.html">←&nbsp; Back to registration</a>
			</div>
		</section>
		<div class="page-footer">Library Management System&nbsp; · &nbsp;Book Registration and Display</div>
	</main>
</body>
</html>
