# Uncomment the next line to define a global platform for your project
# インストール方法
#cd /Users/alirezamesgar/dev/ios/iotdevice
#pod install --repo-update
#pod install

platform :ios, '9.0'

workspace 'inkbird'

target 'inkbird' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # Pods for MQTT Client Sample
  pod 'AzureIoTUtility', '=1.5.0'
  pod 'AzureIoTuMqtt', '=1.5.0'
  pod 'AzureIoTuAmqp', '=1.5.0'
  pod 'AzureIoTHubClient', '=1.5.0'
  #pod 'OpenSSL-Universal'
end
#post_install do |installer|
#  installer.pods_project.build_configurations.each do |config|
#    config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "arm64"
#  end
#end
