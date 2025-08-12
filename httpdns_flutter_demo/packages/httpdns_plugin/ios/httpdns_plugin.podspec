Pod::Spec.new do |s|
  s.name             = 'httpdns_plugin'
  s.version          = '0.0.1'
  s.summary          = 'HTTPDNS plugin providing native resolution via platform SDKs.'
  s.description      = <<-DESC
HTTPDNS Flutter plugin. iOS integrates via CocoaPods. Fill in the vendor framework dependencies below.
  DESC
  s.homepage         = 'https://example.com/httpdns_plugin'
  s.license          = { :type => 'MIT' }
  s.author           = { 'YourName' => 'you@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.ios.deployment_target = '10.0'
  s.swift_version    = '5.0'

  s.dependency 'Flutter'
  # 引入阿里云 HTTPDNS CocoaPods 依赖（按官方文档）
  s.dependency 'AlicloudHTTPDNS', '3.2.1'

  s.static_framework = true
end


