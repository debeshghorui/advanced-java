import java.sql.*;
import java.util.Scanner;

public class dao {

    public static void create() {
        Connection connection = dbconnection.getInstance().getConnection();

        try {
            PreparedStatement ps = connection.prepareStatement(
                    "create table employee(" +
                    "eid number(5) primary key," +
                    "ename varchar2(10)," +
                    "salary number(6))"
            );

            int result = ps.executeUpdate();
            System.out.println(result);

        } catch (Exception e) {
            System.out.println(e);
        }
    }

    public static boolean add() {
        Connection con = dbconnection.getInstance().getConnection();

        try {
            PreparedStatement ps = con.prepareStatement(
                    "insert into employee values(?,?,?)"
            );

            Scanner sc = new Scanner(System.in);

            System.out.println("Enter your id :");
            int id = sc.nextInt();
            ps.setInt(1, id);

            sc.nextLine();

            System.out.println("Enter name :");
            String name = sc.nextLine();
            ps.setString(2, name);

            System.out.println("Enter salary :");
            int sal = sc.nextInt();
            ps.setInt(3, sal);

            int result = ps.executeUpdate();

            if (result > 0) {
                return true;
            }

        } catch (Exception e) {
            System.out.println(e);
        }

        return false;
    }

    public static void view() {
        Connection con = dbconnection.getInstance().getConnection();

        try {
            PreparedStatement ps = con.prepareStatement(
                    "select * from employee"
            );

            ResultSet rs = ps.executeQuery();

            System.out.println();
            System.out.println("ID\t\tNAME\t\tSALARY");

            while (rs.next()) {
                int id = rs.getInt(1);
                String name = rs.getString(2);
                int salary = rs.getInt(3);

                System.out.println();
                System.out.println(id + "\t\t" + name + "\t\t" + salary);
            }

        } catch (SQLException e) {
            System.out.println(e);
        }
    }

    public static boolean delete() {
        Connection con = dbconnection.getInstance().getConnection();

        try {
            PreparedStatement ps = con.prepareStatement(
                    "delete from employee where eid = ?"
            );

            Scanner kb = new Scanner(System.in);

            System.out.println("Enter EID to delete employee :");
            int id = kb.nextInt();
            ps.setInt(1, id);

            int result = ps.executeUpdate();

            if (result > 0) {
                return true;
            }

        } catch (SQLException e) {
            System.out.println(e);
        }

        return false;
    }

    public static boolean update() {
        Connection con = dbconnection.getInstance().getConnection();

        try {
            PreparedStatement ps = con.prepareStatement(
                    "update employee set salary = ? where eid = ?"
            );

            Scanner scan = new Scanner(System.in);

            System.out.println("Enter ID for update detail :");
            int id = scan.nextInt();

            System.out.println("Enter new salary :");
            int sal = scan.nextInt();

            ps.setInt(1, sal);
            ps.setInt(2, id);

            int result = ps.executeUpdate();

            if (result > 0) {
                return true;
            }

        } catch (SQLException e) {
            e.printStackTrace();
        }

        return false;
    }

    public static void exit() {
        try {
            Connection con = dbconnection.getInstance().getConnection();
            if (con != null && !con.isClosed()) {
                con.close();
            }
            System.exit(0);
        } catch (Exception e) {
            System.out.println(e);
        }
    }
}