project 'TickKey.xcodeproj', 'Debug' => :debug, 'Release' => :release
use_frameworks! :linkage => :static

def install_lookin_server
  # 新版 Server subspec 已包含 Base、Core、Shared，避免重复链接底层类。
  source = if %w[1 true yes].include?(ENV['kUse_Local_Lookin'].to_s.downcase)
    { :path => ENV.fetch('LOOKIN_LOCAL_PATH', '../LookInsideWorkspace/LookInside') }
  else
    {
      :git => 'https://github.com/wangwanjie/LookInside.git',
      :commit => '026e36f9b51202aac51e82c213c1cc4f86fc844a'
    }
  end
  pod 'LookinServer', source.merge(:configurations => ['Debug'])
end

post_install do |installer|
  # Xcode 27 已移除旧 SDK 部署范围，将 Pod 下限对齐应用现有下限。
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      { 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0', 'MACOSX_DEPLOYMENT_TARGET' => '12.0' }.each do |setting, minimum|
        current = config.build_settings[setting]
        next unless current

        config.build_settings[setting] = [Gem::Version.new(current), Gem::Version.new(minimum)].max.to_s
      end
    end
  end
end

target 'TickKey' do
  platform :ios, '15.0'
  install_lookin_server

  target 'TickKeyTests' do
    inherit! :search_paths
  end
end

target 'TickKeyMac' do
  platform :osx, '12.0'
  install_lookin_server

  target 'TickKeyMacTests' do
    inherit! :search_paths
  end
end
