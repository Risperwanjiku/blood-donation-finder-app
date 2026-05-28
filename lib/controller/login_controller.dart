import 'package:get/get.dart';

class LoginController extends GetxController{
  var itsLoginIn=false.obs;
  var status="Not logged in".obs;
  setItsLoginIn(value){
    itsLoginIn.value=value;
    status.value="Logged in";
  }
}