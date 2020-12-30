// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import UIKit
import AzureIoTHubClient
import Foundation
import CoreBluetooth
import CoreLocation


let inkbirdServiceCBUUID = CBUUID(string: "0xFFF0")
let battaryUUID = CBUUID(string: "0xFFF1")
let dataCBUUID = CBUUID(string: "0xFFF2")
// Azure IoTHub 送信間隔（60秒 * 1 = 1分）
let MessageSendInterval:Double = Double(60.0 * 1)
// Azure IoTHub 受信間隔（1秒）
let MessageReceiveInterval:Double = Double(1/*60.0 * 30*/)

class ViewController: UIViewController, CLLocationManagerDelegate, UITextFieldDelegate {
    
    //Put you connection string here
    private let connectionString = ""

    // Select your protocol of choice: MQTT_Protocol, AMQP_Protocol or HTTP_Protocol
    // Note: HTTP_Protocol is not currently supported
    private let iotProtocol: IOTHUB_CLIENT_TRANSPORT_PROVIDER = MQTT_Protocol
    
    // IoT hub handle
    private var iotHubClientHandle: IOTHUB_CLIENT_LL_HANDLE!;
    
//    let motionManager = CMMotionManager()
//    /// ロケーションマネージャ
    let locationManager = CLLocationManager()
    
    var cntSent = 0
    var cntGood: Int = 0
    var cntBad = 0
    var cntRcvd = 0
    var randomTelem : String!
    
    // Timers used to control message and polling rates
    var timerMsgRate: Timer!
    var timerDoWork: Timer!
    
    // 緯度
    var latitude  : String? = ""
    // 経度
    var longitude  : String? = ""
    // 都市
    var city :  String? = ""
    // 国
    var country :  String? = ""
    
    // UI elements
    @IBOutlet weak var btnStart: UIButton!
    @IBOutlet weak var btnStop: UIButton!
    @IBOutlet weak var lblSent: UILabel!
    @IBOutlet weak var lblGood: UILabel!
    @IBOutlet weak var lblBad: UILabel!
    @IBOutlet weak var lblRcvd: UILabel!
    @IBOutlet weak var lblLastTemp: UILabel!
    @IBOutlet weak var lblLastHum: UILabel!
    @IBOutlet weak var lblLastRcvd: UILabel!
    @IBOutlet weak var lblLastSent: UILabel!

    @IBOutlet weak var lblDate: UILabel!

    @IBOutlet weak var txtDeviceID: UITextField!
    @IBOutlet weak var lblLocation: UILabel!
    
    var centralManager: CBCentralManager!
    var inkbirdPeripheral: CBPeripheral!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // start scaning for inkbird BLE
//        centralManager = CBCentralManager(delegate: self, queue: nil)
//        centralManager.scanForPeripherals(withServices: nil)
        // get the iPhone GPS location
        locationManager.requestAlwaysAuthorization()
        locationManager.requestWhenInUseAuthorization()
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
        self.txtDeviceID.delegate = self
        self.txtDeviceID.text = "inkbird" // UIDevice.current.name
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
    func fetchCityAndCountry(from location: CLLocation, completion: @escaping (_ city: String?, _ country:  String?, _ error: Error?) -> ()) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            completion(placemarks?.first?.locality,
                       placemarks?.first?.country,
                       error)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locValue: CLLocationCoordinate2D = manager.location?.coordinate else { return }
        //print("locations = \(locValue.latitude) \(locValue.longitude)")
        self.latitude = String(format: "%.6f", locValue.latitude)
        self.longitude = String(format: "%.6f", locValue.longitude)
        self.lblLocation.text = "lat:\(self.latitude!) lon:\(self.longitude!)"
        guard let location: CLLocation = manager.location else { return }
        fetchCityAndCountry(from: location) { city, country, error in
            guard let city = city, let country = country, error == nil else { return }
            //print(city + ", " + country)
            self.city = city
            self.country = country
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    /// Increments the messages sent count and updates the UI
    func incrementSent() {
        cntSent += 1
        lblSent.text = String(cntSent)
    }
    
    /// Increments the messages successfully received and updates the UI
    func incrementGood() {
        cntGood += 1
        lblGood.text = String(cntGood)
    }
    
    /// Increments the messages that failed to be transmitted and updates the UI
    func incrementBad() {
        cntBad += 1
        lblBad.text = String(cntBad)
    }
    
    func incrementRcvd() {
        cntRcvd += 1
        lblRcvd.text = String(cntRcvd)
    }
    
    func json(from object:Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return nil
        }
        return String(data: data, encoding: String.Encoding.utf8)
    }


    func updateTelem() {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .long //Set time style
        dateFormatter.dateStyle = .long //Set date style
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let localDate = dateFormatter.string(from: date)

        

        
        let data : [String : String] = ["datetime":localDate,
                                        "deviceid":self.txtDeviceID.text!,
                                        "lat":self.latitude!,
                                        "lon":self.longitude!,
                                        "temperature":lblLastTemp.text!,
                                        "humidity":lblLastHum.text!,
                                        "city":self.city!,
                                        "country":self.country!]
        randomTelem = json(from:data as Any)
        lblDate.text = "送信日時：\(localDate)"

    }

    
    @objc func DiscoverInkbird( ){
        print("Time作動：DiscoverInkbird")
        // Notifyがサポートされていないセンサーなので、毎回接続する
        centralManager = CBCentralManager(delegate: self, queue: nil)
        centralManager.scanForPeripherals(withServices: nil)
    }
    
    
    /// Sends a message to the IoT hub
    /// controled by [timerMsgRate] timer(every 3 seconds)
    @objc func sendMessage() {
        
        var messageString: String!

        updateTelem()

        // This the message
        messageString = randomTelem
        lblLastSent.text = messageString
        
        
        // Construct the message
        let messageHandle: IOTHUB_MESSAGE_HANDLE = IoTHubMessage_CreateFromByteArray(messageString, messageString.utf8.count)
        
        if (messageHandle != OpaquePointer.init(bitPattern: 0)) {
            
            // Manipulate my self pointer so that the callback can access the class instance
            let that = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            
            if (IOTHUB_CLIENT_OK == IoTHubClient_LL_SendEventAsync(iotHubClientHandle, messageHandle, mySendConfirmationCallback, that)) {
                incrementSent()
            }
        }
        
        //
        // IoTHubClient_LL_DoWork(iotHubClientHandle)
    }
    
    /// Check for waiting messages and send any that have been buffered
    @objc func dowork() {
        IoTHubClient_LL_DoWork(iotHubClientHandle)
    }
    
    /// Display an error message
    ///
    /// parameter message: The message to display
    /// parameter startState: Start button will be set to this state
    /// parameter stopState: Stop button will be set to this state
    func showError(message: String, startState: Bool, stopState: Bool) {
        btnStart.isEnabled = startState
        btnStop.isEnabled = stopState
        print(message)
    }
    
    // This function will be called when a message confirmation is received
    //
    // This is a variable that contains a function which causes the code to be out of the class instance's
    // scope. In order to interact with the UI class instance address is passed in userContext. It is
    // somewhat of a machination to convert the UnsafeMutableRawPointer back to a class instance
    let mySendConfirmationCallback: IOTHUB_CLIENT_EVENT_CONFIRMATION_CALLBACK = { result, userContext in
        
        var mySelf: ViewController = Unmanaged<ViewController>.fromOpaque(userContext!).takeUnretainedValue()
        
        if (result == IOTHUB_CLIENT_CONFIRMATION_OK) {
            mySelf.incrementGood()
        }
        else {
            mySelf.incrementBad()
        }
    }
    
    // This function is called when a message is received from the IoT hub. Once again it has to get a
    // pointer to the class instance as in the function above.
    let myReceiveMessageCallback: IOTHUB_CLIENT_MESSAGE_CALLBACK_ASYNC = { message, userContext in
        
        var mySelf: ViewController = Unmanaged<ViewController>.fromOpaque(userContext!).takeUnretainedValue()
        
        var messageId: String!
        var correlationId: String!
        var size: Int = 0
        var buff: UnsafePointer<UInt8>?
        var messageString: String = ""
        
        messageId = String(describing: IoTHubMessage_GetMessageId(message))
        correlationId = String(describing: IoTHubMessage_GetCorrelationId(message))
        
        if (messageId == nil) {
            messageId = "<nil>"
        }
        
        if correlationId == nil {
            correlationId = "<nil>"
        }
        
        mySelf.incrementRcvd()
        
        // Get the data from the message
        var rc: IOTHUB_MESSAGE_RESULT = IoTHubMessage_GetByteArray(message, &buff, &size)
        
        if rc == IOTHUB_MESSAGE_OK {
            // Print data in hex
            for i in 0 ..< size {
                let out = String(buff![i], radix: 16)
                print("0x" + out, terminator: " ")
            }
            
            print()
            
            // This assumes the received message is a string
            let data = Data(bytes: buff!, count: size)
            messageString = String.init(data: data, encoding: String.Encoding.utf8)!
            
            print("Message Id:", messageId ?? "NULL", " Correlation Id:", correlationId ?? "NULL")
            print("Message:", messageString)
            mySelf.lblLastRcvd.text = messageString
        }
        else {
            print("Failed to acquire message data")
            mySelf.lblLastRcvd.text = "Failed to acquire message data"
        }
        return IOTHUBMESSAGE_ACCEPTED
    }
    
    /// Called when the start button is clicked on the UI. Starts sending messages.
    ///
    /// - parameter sender: The clicked button
    @IBAction func startSend(sender: UIButton!) {
        
        // Dialog box to show action received
        btnStart.isEnabled = false
        btnStart.backgroundColor = UIColor.gray
        btnStop.backgroundColor = UIColor.systemGreen
        btnStop.isEnabled = true
        cntSent = 0
        lblSent.text = String(cntSent)
        cntGood = 0
        lblGood.text = String(cntGood)
        cntBad = 0
        lblBad.text = String(cntBad)
        
        // Create the client handle
        iotHubClientHandle = IoTHubClient_LL_CreateFromConnectionString(connectionString, iotProtocol)
        
        if (iotHubClientHandle == nil) {
            showError(message: "Failed to create IoT handle", startState: true, stopState: false)
            
            return
        }
        
        // Mangle my self pointer in order to pass it as an UnsafeMutableRawPointer
        let that = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        // Set up the message callback
        if (IOTHUB_CLIENT_OK != (IoTHubClient_LL_SetMessageCallback(iotHubClientHandle, myReceiveMessageCallback, that))) {
            showError(message: "Failed to establish received message callback", startState: true, stopState: false)
            
            return
        }
        
        // Timer for message sends and timer for message polls
        timerMsgRate = Timer.scheduledTimer(timeInterval: MessageSendInterval, target: self, selector: #selector(DiscoverInkbird), userInfo: nil, repeats: true)
        timerDoWork = Timer.scheduledTimer(timeInterval: MessageReceiveInterval, target: self, selector: #selector(dowork), userInfo: nil, repeats: true)
    }
    
    /// Called when the stop button is clicked on the UI. Stops sending messages and cleans up.
    ///
    /// - parameter sender: The clicked button
    @IBAction public func stopSend(sender: UIButton!) {
        
        timerMsgRate?.invalidate()
        timerDoWork?.invalidate()
        IoTHubClient_LL_Destroy(iotHubClientHandle)
        btnStart.isEnabled = true
        btnStop.isEnabled = false
        btnStart.backgroundColor = UIColor.systemBlue
        btnStop.backgroundColor = UIColor.gray
    }
}
extension UITextField{
    
    @IBInspectable var doneAccessory: Bool{
        get{
            return self.doneAccessory
        }
        set (hasDone) {
            if hasDone{
                addDoneButtonOnKeyboard()
            }
        }
    }
    
    func addDoneButtonOnKeyboard()
    {
        let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        doneToolbar.barStyle = .default
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done: UIBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(self.doneButtonAction))
        
        let items = [flexSpace, done]
        doneToolbar.items = items
        doneToolbar.sizeToFit()
        
        self.inputAccessoryView = doneToolbar
    }
    
    @objc func doneButtonAction()
    {
        self.resignFirstResponder()
    }
}

extension ViewController: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
      case .unknown:
        print("central.state is .unknown")
      case .resetting:
        print("central.state is .resetting")
      case .unsupported:
        print("central.state is .unsupported")
      case .unauthorized:
        print("central.state is .unauthorized")
      case .poweredOff:
        print("central.state is .poweredOff")
      case .poweredOn:
        print("central.state is .poweredOn")
        centralManager.scanForPeripherals(withServices: [inkbirdServiceCBUUID] /*[heartRateServiceCBUUID]*/)
      @unknown default:
        print("central.state is .unknown")
    }
    

  }
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    
    //print(peripheral)
    let deviceName: String? = peripheral.name
    print(deviceName == nil ? deviceName ?? "N/A" : deviceName!)
    if (deviceName == "sps") {
      print(peripheral)
      inkbirdPeripheral = peripheral
      inkbirdPeripheral.delegate = self
      centralManager.stopScan()
      
      centralManager.connect(inkbirdPeripheral)

    }

  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Successfully Connected!")
    inkbirdPeripheral.discoverServices(nil)

  }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            // Handle error
            print (error)
            return
        }
        print("Successfully Disconnected!")
    }
    
//    // In CBPeripheralDelegate class/extension
//    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
//        if let error = error {
//            // Handle error
//            print (error)
//            return
//        }
//
//        // Successfully subscribed to or unsubscribed from notifications/indications on a chara
//    }
}

extension ViewController: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let services = peripheral.services else { return }
    for service in services {
      print(service)
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let characteristics = service.characteristics else { return }

    for characteristic in characteristics {
      print("characteristic: \(characteristic)")

      if characteristic.properties.contains(.read) {
        print("\(characteristic.uuid): properties contains .read")
        peripheral.readValue(for: characteristic)
      }
      if characteristic.properties.contains(.notify) {
        print("\(characteristic.uuid): properties contains .notify")
        peripheral.setNotifyValue(true, for: characteristic)
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    switch characteristic.uuid {
    case battaryUUID:
      GetBattery(from: characteristic)
    case dataCBUUID:
      GetTemperature(from: characteristic)
      // 切断する
      centralManager.cancelPeripheralConnection(inkbirdPeripheral)
    default:
      print("")
    }
  }
    
  private func GetBattery(from characteristic: CBCharacteristic) {
    guard let characteristicData = characteristic.value else { return }
    // UInt8: "An 8-bit unsigned integer value type."
    let byteArray = [UInt8](characteristicData)
    print("battery: \(Int(byteArray[7]))%")

  }
  
  private func GetTemperature(from characteristic: CBCharacteristic) {
    guard let characteristicData = characteristic.value else { return }
    if(characteristicData.count != 7){ return }
    // UInt8: "An 8-bit unsigned integer value type."
    let buffer = [UInt8](characteristicData)
    print("\(characteristic.uuid): \(buffer)")
    print(buffer.map { String(format: "%02X", $0)})
    

    let byteArray = [UInt8](characteristicData)
    
    var bytes: [UInt8] = [byteArray[0],byteArray[1]]
    var u64le: UInt64 = Data(bytes).toInteger(endian: .little)
    self.lblLastTemp.text = "\(Float(u64le) / 100)"
    print("temperature: \(Float(u64le) / 100)°")
    bytes = [byteArray[2],byteArray[3]]
    u64le = Data(bytes).toInteger(endian: .little)
    self.lblLastHum.text = "\(Float(u64le) / 100)"
    print("humidity: \(Float(u64le) / 100)%")
    sendMessage()
  }
  
  
}
public enum Endian {
    case big, little
}

protocol IntegerTransform: Sequence where Element: FixedWidthInteger {
    func toInteger<I: FixedWidthInteger>(endian: Endian) -> I
}

extension IntegerTransform {
    func toInteger<I: FixedWidthInteger>(endian: Endian) -> I {
        let f = { (accum: I, next: Element) in accum &<< next.bitWidth | I(next) }
        return endian == .big ? reduce(0, f) : reversed().reduce(0, f)
    }

}

extension Data: IntegerTransform {}
extension Array: IntegerTransform where Element: FixedWidthInteger {}
