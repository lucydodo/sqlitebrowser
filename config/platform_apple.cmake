# For Apple Silicon Mac's and install dependencies via our Homebrew tap(sqlitebrowser/homebrew-tap)
if(customTap AND EXISTS /opt/homebrew/opt/)
    if(QT_MAJOR STREQUAL "Qt5")
        list(PREPEND CMAKE_PREFIX_PATH "/opt/homebrew/opt/sqlb-qt@5")
    elseif(QT_MAJOR STREQUAL "Qt6")
        list(PREPEND CMAKE_PREFIX_PATH "/opt/homebrew/opt/qt")
    endif()

    if(sqlcipher)
        list(APPEND SQLCIPHER_INCLUDE_DIR "/opt/homebrew/include")
        list(APPEND SQLCIPHER_LIBRARY "/opt/homebrew/opt/sqlb-sqlcipher/lib/libsqlcipher.0.dylib")
    else()
        list(PREPEND CMAKE_PREFIX_PATH "/opt/homebrew/opt/sqlb-sqlite")
    endif()
endif()

set_target_properties(${PROJECT_NAME} PROPERTIES
    BUNDLE True
    OUTPUT_NAME "DB Browser for SQLite"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/app.plist
)
