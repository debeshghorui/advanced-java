<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Display Books</title>
<style>
	body {
		font-family: Arial, sans-serif;
		background-color: #f4f4f4;
		margin: 0;
	}
	h1 {
		text-align: center;
		background-color: #2c3e50;
		color: white;
		padding: 15px;
		margin: 0 0 30px 0;
	}
	.container {
		width: 95%;
		margin: 0 auto;
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		background-color: white;
		box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
	}
	th, td {
		border: 1px solid #ccc;
		padding: 10px;
		text-align: center;
	}
	th {
		background-color: #2c3e50;
		color: white;
	}
	tr:nth-child(even) {
		background-color: #f2f2f2;
	}
	.link {
		display: block;
		text-align: center;
		margin: 20px 0;
	}
</style>
</head>
<body>
	<h1>Library Management System - Book Records</h1>
	<div class="container">
		<table>
			<tr>
				<th>Book Id</th>
				<th>Book Title</th>
				<th>Author Name</th>
				<th>Publisher Name</th>
				<th>Category</th>
				<th>Edition</th>
				<th>Publication Year</th>
				<th>Price</th>
				<th>Quantity</th>
			</tr>
			<%
				java.util.ArrayList<String> books = (java.util.ArrayList<String>) request.getAttribute("books");
				if (books != null) {
					for (String row : books) {
						String[] cols = row.split("\\|");
				%>
			<tr>
				<% for (String col : cols) { %>
					<td><%= col %></td>
				<% } %>
			</tr>
			<%
					}
				} else {
				%>
			<tr>
				<td colspan="9">No books registered yet.</td>
			</tr>
			<%
				}
			%>
		</table>
		<a class="link" href="index.html">Back to Registration Page</a>
	</div>
</body>
</html>
