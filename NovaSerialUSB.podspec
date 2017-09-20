Pod::Spec.new do |spec|

    spec.name                   = 'NovaSerialUSB'
    spec.version                = '0.5'
    spec.summary                = 'Swifty Class for Reading / Writing to USB Serial Device'

    spec.homepage               = 'https://github.com/netizen01/NovaSerialUSB'
    spec.license                = { :type => 'MIT', :file => 'LICENSE' }
    spec.author                 = { 'Netizen01' => 'n01@invco.de' }

    spec.osx.deployment_target  = '10.11'

    spec.source                 = { :git => 'https://github.com/netizen01/NovaSerialUSB.git',
                                    :tag => spec.version.to_s }
    spec.source_files           = 'Source/**/*.swift'
    spec.pod_target_xcconfig    = { 'SWIFT_VERSION' => '4.0' }

end
