include(${CMAKE_CURRENT_LIST_DIR}/esp8266.cmake)

# macro arduino
# usage:
# arduino(executable_name library1 library2 library3 ...)
# example:
# add_executable(firmware ${USER_SOURCES})
# arduino(firmware ESP8266WiFi Servo)
macro(arduino)
    # first argument - name of executable project, other - library names
    set(ARGUMENTS ${ARGN})
    list(GET ARGUMENTS 0 PROJECT_NAME)
    list(REMOVE_AT ARGUMENTS 0)

    # esp8266 core files
    file(GLOB_RECURSE CORE_ASM_ITEMS "${HARDWARE_ROOT}/cores/esp8266/*.S")
    file(GLOB_RECURSE CORE_C_ITEMS "${HARDWARE_ROOT}/cores/esp8266/*.c")
    file(GLOB_RECURSE CORE_CXX_ITEMS "${HARDWARE_ROOT}/cores/esp8266/*.cpp")
    
    # create core library
    add_library(arduino_core STATIC ${CORE_ASM_ITEMS} ${CORE_C_ITEMS} ${CORE_CXX_ITEMS})

    # esp8266 include directories
    include_directories(
            ${HARDWARE_ROOT}/tools/sdk/include
            ${HARDWARE_ROOT}/tools/sdk/lwip2/include
            ${HARDWARE_ROOT}/tools/sdk/libc/xtensa-lx106-elf/include
            ${HARDWARE_ROOT}/cores/esp8266
            ${HARDWARE_ROOT}/variants/nodemcu
            )


    # and esp8266 build definitions
    set(COMPILE_DEFS        
	    -D__ets__
            -DICACHE_FLASH
            -DF_CPU=80000000L
            -DLWIP_OPEN_SRC
	    -DTCP_MSS=536
	    -DLWIP_FEATURES=1
	    -DLWIP_IPV6=0
            -DARDUINO=10612
            -DARDUINO_ESP8266_NODEMCU
            -DARDUINO_ARCH_ESP8266
            -DARDUINO_BOARD="ESP8266_NODEMCU"
            -DESP8266
	    -DVTABLES_IN_FLASH
	    -DNONOSDK221=1
	    -DFLASHMODE_DIO
            )

    target_compile_definitions(arduino_core PUBLIC ${COMPILE_DEFS})

    
    target_link_libraries(${PROJECT_NAME} PUBLIC arduino_core)

    # some other options and link libraries
    target_compile_options(arduino_core PUBLIC -U__STRICT_ANSI__)
    target_link_libraries(arduino_core PUBLIC hal phy pp net80211 lwip2-536-feat wpa crypto main wps bearssl axtls espnow smartconfig airkiss wpa2 stdc++ m c gcc)


    # empty lists of library files and include direcories
    set(LIBRARIES_FILES)
    set(LIBRARY_INCLUDE_DIRECTORIES)

    # for each every library determine it's sources and include directories
    foreach(ITEM ${ARGUMENTS})
        # library can be located in 3 different places. 
        # user files located under documents folder
        set(LIBRARY_HOME ${USER_LIBRARIES_ROOT}/${ITEM})
        if(NOT EXISTS ${LIBRARY_HOME})
            # if no user library, look into esp8266 hardware libraries
            set(LIBRARY_HOME ${ESP8266_LIBRARIES_ROOT}/${ITEM})
            if(NOT EXISTS ${LIBRARY_HOME})
                # last chance that it be arduino standard library (as servo or SD)
                set(LIBRARY_HOME ${SYSTEM_LIBRARIES_ROOT}/${ITEM})
                if(NOT EXISTS ${LIBRARY_HOME})
                    message( FATAL_ERROR "Library ${ITEM} does not found")
                endif()
            endif()
        endif()
        # look for library source files
        file(GLOB_RECURSE LIBRARY_S_FILES ${LIBRARY_HOME}/*.S)
        file(GLOB_RECURSE LIBRARY_C_FILES ${LIBRARY_HOME}/*.c)
        file(GLOB_RECURSE LIBRARY_X_FILES ${LIBRARY_HOME}/*.cpp)
        # and append it to library sources list
        list(APPEND LIBRARIES_FILES ${LIBRARY_S_FILES} ${LIBRARY_c_FILES} ${LIBRARY_X_FILES})
        # also look into header files
        file(GLOB_RECURSE LIBRARY_H_FILES ${LIBRARY_HOME}/*.h ${LIBRARY_HOME}/*.hpp)
        foreach(HEADER_FILE ${LIBRARY_H_FILES})
            get_filename_component(HEADER_DIRECTORY ${HEADER_FILE} DIRECTORY)
            list(APPEND LIBRARY_INCLUDE_DIRECTORIES ${HEADER_DIRECTORY})
        endforeach()
	add_library(${ITEM} ${LIBRARY_S_FILES} ${LIBRARY_C_FILES} ${LIBRARY_X_FILES})
	include_directories(${LIBRARY_HOME}/ ${LIBRARY_HOME}/src/) 
	target_compile_definitions(${ITEM} PUBLIC ${COMPILE_DEFS})
	target_link_libraries(${PROJECT_NAME} PUBLIC ${ITEM})
    endforeach()
    # exclude header directories duplicates
    list(REMOVE_DUPLICATES LIBRARY_INCLUDE_DIRECTORIES)

    # costum target for pre linking to generate local.eagle.app.v6.common.ld
    add_custom_command(TARGET ${PROJECT_NAME} PRE_LINK COMMAND ${CMAKE_C_COMPILER} -CC -E -P -DVTABLES_IN_FLASH "${HARDWARE_ROOT}/tools/sdk/ld/eagle.app.v6.common.ld.h" -o "${HARDWARE_ROOT}/tools/sdk/ld/local.eagle.app.v6.common.ld")

    target_link_directories(${PROJECT_NAME} PUBLIC "${HARDWARE_ROOT}/tools/sdk/ld/")

    # command to create bin file (2.5.2)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
		COMMAND "${ARDUINO_ESP8266_HOME}/tools/python/3.7.2-post1/python" "${HARDWARE_ROOT}/tools/elf2bin.py" --eboot "${HARDWARE_ROOT}/bootloaders/eboot/eboot.elf" --app $<TARGET_FILE:firmware> --flash_mode dio --flash_freq 40 --flash_size 4M --path "${TOOLCHAIN_BIN}" --out $<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.bin
		COMMENT "Building ${PROJECT_NAME}> bin file")

    ## For Flashing    
    if(NOT RESET_METHOD)
	set(RESET_METHOD "none")
	message("RESET_METHOD not set (Default='none')")
    endif()
    
    if(NOT BAUD_RATE)
	set(BAUD_RATE "115200")
	message("BAUD_RATE not set (Default='115200')")
    endif()

    if(NOT PORT AND CMAKE_HOST_SYSTEM_NAME MATCHES "Darwin")
	set(PORT "/dev/tty.usbserial")
	message("PORT not set (Default='/dev/tty.usbserial')")
    elseif(NOT PORT AND CMAKE_HOST_SYSTEM_NAME MATCHES "Windows")
	set(PORT "COM1")
	message("PORT not set (Default='COM1')")
    endif()

    add_custom_target(flash COMMAND ${ESPTOOL_APP} -cd ${RESET_METHOD} -cb ${BAUD_RATE} -cp ${PORT} -cf "${PROJECT_NAME}.bin")

endmacro()
