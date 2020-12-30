# Send Inkbird iBS-TH1 data to Azure IoTHub
**プロジェクトの概要：** iPhoneを経由して、プローブ付きのセンサーデータ（温度、湿度、日時、緯度経度）をAzure IoTHubに送信する

**利用シナリオ：** 車やトラックなどで移動するとき、温湿度及び位置情報を（ゲートウエイなしで）iPhone経由でAzure IoTHubに送信して可視化や蓄積する


[オリジナルプロジェクト](https://github.com/Azure-Samples/azure-iot-samples-ios/tree/master/)

イメージ図

![イメージ図](https://github.com/mesgar/inkbird/blob/main/image.png?raw=true)

## Build
1. git clone https://github.com/mesgar/inkbird/ inkbird</br>
2. cd inkbird</br>
3. pod install</br>
4. open [inkbird.xcworkspace] with xcode and build</br>

## Settings
1. Add [NSBluetoothAlwaysUsageDescription] [Wants to use bluetooth] to plist.info
2. Set your IoTHub Connection string in ViewController.swift
