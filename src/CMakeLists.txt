# folder: src
#         ---

FIND_PACKAGE(wxWidgets REQUIRED html adv core base net aui xrc qa richtext )
INCLUDE(${wxWidgets_USE_FILE})

include_directories( ${PROJECT_SOURCE_DIR}/src/ibpp/core
                     ${PROJECT_SOURCE_DIR}/src/data_interface
) 

# look for TagLib
find_path( TAGLIB_INCLUDE_PATH tag.h PATH_SUFFIXES taglib DOC "Path to TagLib header files" )
message( STATUS "TagLib header files path: " ${TAGLIB_INCLUDE_PATH} )
if(WIN32)
  find_file( TAGLIB_LIB_PATH_DEBUG tagd.lib DOC "Path to the DEBUG TagLib library" )
  find_file( TAGLIB_LIB_PATH_RELEASE tag.lib DOC "Path to the RELEASE TagLib library" )
elseif(APPLE)
  # Homebrew only ships the shared library; MACOSX_fixup_bundle.sh copies it into the bundle
  find_library( TAGLIB_LIB tag )
  if( NOT TAGLIB_LIB )
    message( FATAL_ERROR "Unable to find TagLib" )
  endif( NOT TAGLIB_LIB )
else(WIN32)
  find_library( TAGLIB_LIB libtag.a PATHS /usr/lib /usr/local/lib )
  if( NOT TAGLIB_LIB )
    message( FATAL_ERROR "Unable to find TagLib" )
  else( NOT TAGLIB_LIB )
    message( STATUS "TagLib: " ${TAGLIB_LIB} )
  endif( NOT TAGLIB_LIB )
endif(WIN32)

include_directories( ${TAGLIB_INCLUDE_PATH} )
if( NOT APPLE )
  add_definitions( -DTAGLIB_STATIC )
endif( NOT APPLE )

if( WIN32 )
  add_definitions( -DIBPP_WINDOWS )
elseif( APPLE )
  add_definitions( -DIBPP_DARWIN )
else( WIN32 )
  add_definitions( -DIBPP_LINUX )
endif( WIN32 )

add_subdirectory( ibpp )
add_subdirectory( data_interface )

link_directories (${PROJECT_BINARY_DIR}/src/ibpp/core
                  ${PROJECT_BINARY_DIR}/src/data_interface
) 


# For convenience we define the sources as a variable. You can add 
# header files and cpp/c files and CMake will sort them out
set( SRCS
  audio_metadata.cpp
  audio_metadata.h
  catalog_volume.cpp
  catalog_volume.h
  catalog_volume_functions.cpp
  catalog_volume_functions.h
  choose_virtual_folder.cpp
  choose_virtual_folder.h
  chooselang.cpp
  chooselang.h
  convert_db_unicode.cpp
  decode_search_string.cpp
  decode_search_string.h
  dlg_file_information.cpp
  dlg_file_information.h
  exportdata.cpp
  exportdata.h
  long_task_beep.cpp
  long_task_beep.h
  mainframe.cpp
  mainframe.h
  mylistitemdata.h
  mytreeitemdata.h
  object_description.cpp
  object_description.h
  opencatalog.cpp
  opencatalog.h
  resource.h
  restore.cpp
  restore.h
  settings.cpp
  settings.h
  update_volume.cpp
  update_volume.h
  utils.cpp
  utils.h
  vvv.cpp
  vvv.h
  window_position.cpp
  window_position.h
)
  

# If we build for windows systems, we also include the resource file
# containing the manifest, icon and other resources
if(WIN32)
  set( SRCS ${SRCS} windows_specific.cpp windows_specific.h vvv.rc vvv.rc2 )
endif(WIN32)

#--------------------------------------------------------------------------------
# For Apple set the icns file containing icons
if(APPLE)
  # icon files to copy in the bundle
  set( OSX_ICON_FILES ${CMAKE_CURRENT_SOURCE_DIR}/graphics/vvv.icns ${CMAKE_CURRENT_SOURCE_DIR}/graphics/vvv-document.icns ) 
  # set where in the bundle to put the icns files
  set_source_files_properties( ${OSX_ICON_FILES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
  # include the icns files in the target
  set( SRCS ${SRCS} ${OSX_ICON_FILES} )
ENDIF(APPLE)

add_executable( vvv WIN32 MACOSX_BUNDLE ${SRCS} )

if(APPLE)
  # configure CMake to use a custom Info.plist
  set_target_properties( vvv PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${PROJECT_SOURCE_DIR}/vvv-Info.plist )
ENDIF(APPLE)

if(WIN32)
  target_link_libraries( vvv debug ${TAGLIB_LIB_PATH_DEBUG} optimized ${TAGLIB_LIB_PATH_RELEASE} )
else(WIN32)
  target_link_libraries( vvv ${TAGLIB_LIB} )
endif(WIN32)
target_link_libraries(vvv data_interface ibpp ${wxWidgets_LIBRARIES})
if( APPLE )
  # Firebird 5 runtime extracted from the official arm64 pkg by scripts/fetch-firebird.sh
  set( FIREBIRD_ROOT ${PROJECT_SOURCE_DIR}/deps/fb5/Resources CACHE PATH "Firebird 5 Resources folder" )
  find_library( FB_LIB fbclient PATHS ${FIREBIRD_ROOT}/lib NO_DEFAULT_PATH )
  if( NOT FB_LIB )
    message( FATAL_ERROR "Unable to find libfbclient in ${FIREBIRD_ROOT}/lib, run scripts/fetch-firebird.sh" )
  endif( NOT FB_LIB )
  message( STATUS "Firebird interface: " ${FB_LIB} )
  target_link_libraries( vvv ${FB_LIB} )
elseif( UNIX )
  # link to the Firebird client library
  # the last path is used for OS X where I have a local copy (not installed)
  find_library( FB_LIB fbembed PATHS /usr/lib /usr/local/lib /opt/firebird/lib ${PROJECT_SOURCE_DIR}/firebird_runtime/firebird )
  if( NOT FB_LIB )
    message( FATAL_ERROR "Unable to find firebird interface" )
  else( NOT FB_LIB )
    message( STATUS "Firebird interface: " ${FB_LIB} )
  endif( NOT FB_LIB )

  # look for the folder containing the firebird embedded files to ship with the program
  find_path( FB_EMBEDDED_PATH firebird.conf ${PROJECT_SOURCE_DIR}/firebird_runtime ${PROJECT_SOURCE_DIR}/../../firebird_embedded_2.0.4_runtime )
  message( STATUS "Embedded firebird files path: " ${FB_EMBEDDED_PATH} )

#  target_link_libraries( vvv -lfbembed )
  target_link_libraries( vvv ${FB_LIB} )
endif()


# installation stuff

install( TARGETS vvv DESTINATION . )

if( APPLE )
  # copy the Firebird 5 runtime (embedded engine = libfbclient + plugins/libEngine13), Resources, not Frameworks: it contains data files; vvv.cpp points FIREBIRD at it
  set( FB_BUNDLE_DIR vvv.app/Contents/Resources/firebird )
  install( DIRECTORY ${FIREBIRD_ROOT}/lib ${FIREBIRD_ROOT}/intl ${FIREBIRD_ROOT}/tzdata
           DESTINATION ${FB_BUNDLE_DIR} USE_SOURCE_PERMISSIONS )
  # only the plugins an embedded connection needs (no sample crypt, UDR, trace, profiler)
  install( FILES ${FIREBIRD_ROOT}/plugins/libEngine13.dylib ${FIREBIRD_ROOT}/plugins/libSrp.dylib ${FIREBIRD_ROOT}/plugins/libLegacy_Auth.dylib
           DESTINATION ${FB_BUNDLE_DIR}/plugins )
  install( FILES ${FIREBIRD_ROOT}/firebird.conf ${FIREBIRD_ROOT}/firebird.msg ${FIREBIRD_ROOT}/plugins.conf
                 ${FIREBIRD_ROOT}/databases.conf ${FIREBIRD_ROOT}/security5.fdb ${FIREBIRD_ROOT}/License.txt
           DESTINATION ${FB_BUNDLE_DIR} )
endif( APPLE )

if( UNIX AND NOT APPLE )
  # copy the Firebird runtime
  install( DIRECTORY ${FB_EMBEDDED_PATH}/ DESTINATION . USE_SOURCE_PERMISSIONS )
  # copy other files used only for the Linux version
  install( FILES ${PROJECT_SOURCE_DIR}/linux_specific/readme.txt 
                 ${PROJECT_SOURCE_DIR}/linux_specific/License.txt 
                 DESTINATION . )
  install( FILES ${PROJECT_SOURCE_DIR}/linux_specific/vvv-start.sh 
                 DESTINATION . PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ GROUP_EXECUTE
                                           GROUP_READ WORLD_READ WORLD_EXECUTE )
endif( UNIX AND NOT APPLE )

if( UNIX )
  # set the installation path of the executable file and the resources (in OS X they are inside the bundle )
  if( APPLE )
    set( EXECUTABLE_INTALL_PATH vvv.app/Contents/MacOS )
    set( RESOURCES_INTALL_PATH vvv.app/Contents/Resources )
  else( APPLE )
    set( EXECUTABLE_INTALL_PATH . )
    set( RESOURCES_INTALL_PATH . )
  endif( APPLE )

  # copy localization files -- vvv files...
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-bg.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/bg RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-cs.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/cs RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-de.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/de RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-es.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/es RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-fr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/fr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-gr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/gr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-hr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/hr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-hu.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/hu RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-it.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/it RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-ja.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/ja RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-nl.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/nl RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-pl.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/pl RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-pt.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/pt RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-ro.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/ro RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-ru.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/ru RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-sr.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/sr RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-sr@latin.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/sr@latin RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-uk.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/uk RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-zh_TW.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_TW RENAME vvv.mo )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/vvv-zh_CN.mo 
           DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_CN RENAME vvv.mo )
# ... wxWidgets files
  install( FILES ${PROJECT_SOURCE_DIR}/translations/cs/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/cs )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/de/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/de )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/es/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/es )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/fr/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/fr )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/hr/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/hr )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/hu/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/hu )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/it/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/it )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/ja/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/ja )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/nl/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/nl )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/pl/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/pl )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/pt/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/pt )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/ro/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/ro )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/ru/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/ru )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/sr/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/sr )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/uk/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/uk )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/zh_CN/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_CN )
  install( FILES ${PROJECT_SOURCE_DIR}/translations/zh_TW/wxstd.mo DESTINATION ${RESOURCES_INTALL_PATH}/languages/zh_TW )

#  install( DIRECTORY ${PROJECT_SOURCE_DIR}/translations/ DESTINATION ${RESOURCES_INTALL_PATH}/languages 
#           FILES_MATCHING PATTERN "*.mo"
#           PATTERN ".svn" EXCLUDE )

  # copy other files to the installation path
  install( FILES ${PROJECT_SOURCE_DIR}/vvv-struct-update.fdb 
                 ${PROJECT_SOURCE_DIR}/VVV.fbk
                 ${PROJECT_SOURCE_DIR}/help/en/vvv.htb
                 DESTINATION ${RESOURCES_INTALL_PATH} )  # Contents/Resources on APPLE, see CUtils::GetDataFilesPath

endif( UNIX )

if( APPLE )
  # must stay the last install rule: fixes library references, bundles wxWidgets/TagLib, signs
  # fix library references, bundle wxWidgets/TagLib, sign
  install( CODE "execute_process( COMMAND ${PROJECT_SOURCE_DIR}/MACOSX_fixup_bundle.sh \"\${CMAKE_INSTALL_PREFIX}/vvv.app\" COMMAND_ERROR_IS_FATAL ANY )" )
endif( APPLE )
