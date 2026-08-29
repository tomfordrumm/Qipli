on run arguments
    if (count of arguments) is not 1 then error "expected the mounted volume path"

    set mountedFolder to POSIX file (item 1 of arguments) as alias

    tell application "Finder"
        open mountedFolder
        set installerWindow to container window of mountedFolder
        tell installerWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            set sidebar width to 0
            set bounds to {200, 200, 860, 620}
        end tell

        tell icon view options of installerWindow
            set arrangement to not arranged
            set icon size to 128
            set text size to 14
            set background picture to file ".background:install-background.png" of mountedFolder
        end tell

        set extension hidden of item "Qipli.app" of mountedFolder to true
        set position of item "Qipli.app" of mountedFolder to {185, 225}
        set position of item "Applications" of mountedFolder to {475, 225}
        update mountedFolder without registering applications
        delay 2
        close installerWindow
        delay 1

        open mountedFolder
        set installerWindow to container window of mountedFolder
        set bounds of installerWindow to {200, 200, 860, 620}
        update mountedFolder without registering applications
        delay 2
        close installerWindow
    end tell
end run
