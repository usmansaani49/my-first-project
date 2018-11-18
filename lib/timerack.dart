import 'dart:async';
import 'dart:io';
import 'globals.dart' as globals;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:location/location.dart';
import 'package:flutter/services.dart';
class TimeRackHome extends StatefulWidget {

  @override
  _TimeRackHomeState createState() {
    return _TimeRackHomeState();
  }
}



class _TimeRackHomeState extends State<TimeRackHome> {
  CameraController controller;
  String imagePath;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<CameraDescription> cameras = globals.cameras;
  StreamSubscription<Map<String, double>> _locationSubscription;
  Location _location = new Location();
  bool _permission = false;
  String error;
  Map<String, double> _currentLocation;
  bool currentWidget = true;
  bool apiCall = false;
  String filePath;
  bool _isCheckInOutDisabled;
  var response;
  @override
  void initState() {
    super.initState();

    initPlatformState();

    _locationSubscription =
        _location.onLocationChanged().listen((Map<String,double> result) {
          setState(() {
            _currentLocation = result;
          });
        });
  }
  // Platform messages are asynchronous, so we initialize in an async method.
  initPlatformState() async {
    Map<String, double> location;
    // Platform messages may fail, so we use a try/catch PlatformException.

    try {
      _permission = await _location.hasPermission();
      location = await _location.getLocation();


      error = null;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        error = 'Permission denied';
      } else if (e.code == 'PERMISSION_DENIED_NEVER_ASK') {
        error = 'Permission denied - please ask the user to enable it from the app settings';
      }

      location = null;
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    //if (!mounted) return;

    setState(() {
      _isCheckInOutDisabled = true;
    });

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Time Rack :'+' '+globals.prefs.getString("companyName")+' '+globals.prefs.getString("personName")+'('+globals.prefs.getString("empCode")+')'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(
                  child: _cameraPreviewWidget(),
                ),
              ),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: controller != null && controller.value.isRecordingVideo
                      ? Colors.redAccent
                      : Colors.grey,
                  width: 3.0,
                ),
              ),
            ),
          ),
          _captureControlRowWidget(),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                _punchTogglesRowWidget(),
                new Container(
                  margin: const EdgeInsets.only(left: 20.0),
                  child:RaisedButton(
                          onPressed: (){
                            if(!_isCheckInOutDisabled) {

                              _scaffoldKey.currentState.showSnackBar(
                                  new SnackBar(
                                    duration: new Duration(seconds: 4), content:
                                  new Row(
                                    children: <Widget>[
                                      new CircularProgressIndicator(),
                                      globals.prefs.getInt("inOrOut") == 0
                                          ? new Text("  Checking-Out...")
                                          : new Text("  Checking-In...")
                                    ],
                                  ),
                                  ));
                              punchAttendance().then(updateStateAfterResponse());
                            }
                            },
                          child: globals.prefs.getInt("inOrOut")==0? Text('Check Out'):Text('Check In'),
                          padding: const EdgeInsets.all(8.0),
                          textColor: Colors.white,
                          color: Colors.green,
                        ),
                )
                //_thumbnailWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns a suitable camera icon for [direction].
  IconData getCameraLensIcon(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return Icons.camera_rear;
      case CameraLensDirection.front:
        return Icons.camera_front;
      case CameraLensDirection.external:
        return Icons.camera;
    }
    throw ArgumentError('Unknown lens direction');
  }

  void logError(String code, String message) =>
      print('Error: $code\nError Message: $message');
  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !controller.value.isInitialized) {
      if (cameras.isEmpty) {
        return const Text('No camera found');
      } else {
        onNewCameraSelected(cameras[1]);
      }
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: CameraPreview(controller),
    );
    //}
  }


  Widget _captureControlRowWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.green,
          onPressed: controller != null &&
              controller.value.isInitialized &&
              !controller.value.isRecordingVideo
              ? onTakePictureButtonPressed
              : null,
        ),
      ],
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _punchTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    if (cameras.isEmpty) {
      return const Text('No camera found');
    } else {
      for (CameraDescription cameraDescription in cameras) {
        toggles.add(
          SizedBox(
            width: 90.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: controller != null && controller.value.isRecordingVideo
                  ? null
                  : onNewCameraSelected,
            ),
          )
        );

      }
    }

    return Row(children: toggles);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }
    controller = CameraController(cameraDescription, ResolutionPreset.high);

// If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
      if (controller.value.hasError) {
        //showInSnackBar('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((String filePath) {
      if (mounted) {
        setState(() {
          imagePath = filePath;
          _isCheckInOutDisabled = false;
        });
        //if (filePath != null) showInSnackBar('Picture saved to $filePath');
      }
    });
  }

  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    filePath = '$dirPath/${timestamp()}.jpg';

    if (controller.value.isTakingPicture) {
// A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  punchAttendance() async{

    var dio = new Dio();
    dio.options.baseUrl = "http://www.example.com/api-endpoint";
    dio.options.connectTimeout = 5000; //5s
    dio.options.receiveTimeout=5000;

    FormData formData = new FormData.from({
      "empCode": globals.prefs.getString("empCode"),
      "type": globals.prefs.getInt("inOrOut"),
      "location":_currentLocation["latitude"].toString()+","+ _currentLocation["longitude"].toString(),
      "file": new UploadFileInfo(new File(filePath),globals.prefs.getString("empCode")+'_'+timestamp()+'.jpg')
    });

    // Send FormData
    response = await dio.post("/test", data: formData);

    print(response);
  }

  updateStateAfterResponse() {
        if(response=="OK-Value_fromAPI"){
          _isCheckInOutDisabled = true;
          _scaffoldKey.currentState.showSnackBar(
              new SnackBar(
                duration: new Duration(seconds: 4), content:
              new Row(
                children: <Widget>[
                  globals.prefs.getInt("inOrOut")==0?new Text("Checked Out succesfully"):new Text("Checked In succesfully")
                ],
              ),
              ));
          if(globals.prefs.getInt("inOrOut")==0 || globals.prefs.getInt("inOrOut")==null){
            globals.prefs.setInt("inOrOut",1);
          }else{
            globals.prefs.setInt("inOrOut",0);
          }
          //Navigator.of(context).pushNamed("/");
        }else{
          _isCheckInOutDisabled = true;
          _scaffoldKey.currentState.showSnackBar(
              new SnackBar(
                duration: new Duration(seconds: 4), content:
              new Row(
                children: <Widget>[
                  new Text("Some error occured")
                ],
              ),
              ));
        }
  }
}
