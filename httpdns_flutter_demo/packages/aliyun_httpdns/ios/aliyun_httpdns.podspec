# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint aliyun_httpdns.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'aliyun_httpdns'
  s.version          = '1.0.1'
  s.summary          = 'aliyun httpdns flutter plugin'
  s.description      = <<-DESC
aliyun httpdns flutter plugin.
DESC
  s.homepage         = 'https://help.aliyun.com/document_detail/435220.html'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Aliyun' => 'httpdns@alibaba-inc.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'AlicloudHTTPDNS', '3.3.0'
  s.platform = :ios, '10.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  
  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'aliyun_httpdns_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end


