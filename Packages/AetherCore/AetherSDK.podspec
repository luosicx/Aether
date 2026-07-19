Pod::Spec.new do |s|
  s.name             = 'AetherSDK'
  s.version          = '0.1.0-beta'
  s.summary          = 'Aether SDK — Third-party integration entry for Aether AI assistant.'
  s.description      = <<-DESC
  AetherSDK provides a unified AetherClient for chat / stream / embed / retrieve APIs,
  custom tool registration, multi-provider auth schemes (API Key / OAuth 2.0 / JWT / Device Bound),
  and automatic retry with exponential backoff.

  **DEPRECATED**: This podspec is provided only for legacy CocoaPods projects.
  New integrations SHOULD use Swift Package Manager (SPM) instead:
  https://github.com/Aether/AIBuiler  (Packages/AetherCore)
                       DESC
  s.homepage         = 'https://github.com/Aether/AIBuiler'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Aether Team' => 'dev@aether.example.com' }
  s.source           = { :git => 'https://github.com/Aether/AIBuiler.git', :tag => s.version.to_s }

  s.ios.deployment_target = '17.0'
  s.osx.deployment_target = '14.0'

  # CocoaPods 不支持 SPM binary target（aether_core.xcframework），需手工集成
  # 推荐迁移到 SPM：在 Xcode 中 File > Add Packages > 输入仓库 URL
  s.deprecated      = true
  s.deprecated_in_favor_of = 'AetherCore (SPM)'

  s.source_files = 'Packages/AetherCore/Sources/AetherSDK/**/*.swift'
  s.dependency 'AetherFoundation', '~> 0.1'
  s.dependency 'AetherServices', '~> 0.1'
  s.swift_version = '5.9'
end
