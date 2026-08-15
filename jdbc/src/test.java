import java.util.Scanner;

public class test {

    public static void main(String[] args) {

        Scanner sc = new Scanner(System.in);

        int ch = 0;

        while (true) {

            System.out.println(
                "\n\n1.ADD\n2.DELETE\n3.UPDATE" +
                "\n4.DISPLAY\n5.EXIT\n6.CREATE"
            );

            System.out.println("Enter your choice : ");

            ch = sc.nextInt();

            switch (ch) {
	            case 1:
	
	                if (dao.add()) {
	
	                    System.out.println(
	                        "insertion successfull"
	                    );
	
	                } else {
	
	                    System.out.println(
	                        "insertion unsuccessfull"
	                    );
	                }
	
	                break;
	            case 2:

	                if (dao.delete()) {

	                    System.out.println(
	                        "deletion successfull"
	                    );

	                } else {

	                    System.out.println(
	                        "deletion unsuccessfull"
	                    );
	                }

	                break;
	            
	            case 3:

	                if (dao.update()) {

	                    System.out.println(
	                        "update successfull"
	                    );

	                } else {

	                    System.out.println(
	                        "update unsuccessfull"
	                    );
	                }

	                break;
	                
	            case 4:

	                dao.view();

	                break;
	            case 5:

	                dao.exit();
	                
	            case 6:

	                dao.create();

	                break;
	                
	            default:

	                System.out.println("Wrong Choice..");

            }
        }
    }
}