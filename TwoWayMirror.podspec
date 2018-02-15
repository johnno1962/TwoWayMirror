Pod::Spec.new do |s|
    s.name        = "TwoWayMirror"
    s.version     = "1.1.0"
    s.summary     = "Bi-directional reflection for Swift"
    s.homepage    = "https://github.com/johnno1962/TwoWayMirror"
    s.social_media_url = "https://twitter.com/Injection4Xcode"
    s.documentation_url = "https://github.com/johnno1962/TwoWayMirror/blob/master/README.md"
    s.license     = { :type => "MIT" }
    s.authors     = { "johnno1962" => "mirror@johnholdsworth.com" }

    s.osx.deployment_target = "10.11"
    s.source   = { :git => "https://github.com/johnno1962/TwoWayMirror.git", :tag => s.version }
    s.source_files = "TwoWayMirror.playground/Sources/*.swift"
end
