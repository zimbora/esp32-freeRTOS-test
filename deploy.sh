#!/bin/bash

home_dir="~"
project="esp32-freeRTOS2"
app_folder="test"
app_macro="APP_TEST"

docker=false
libs="WiFi@2.0.0 Update@2.0.0 ArduinoOTA@2.0.0 WebServer@2.0.0
			ESPmDNS@2.0.0 WiFiClientSecure@2.0.0 FS@2.0.0 ESP32 BLE Arduino@2.0.0
			ArduinoJson@6.19.4 ESP32Logger2@1.0.3 EspMQTTClient@1.13.3 PubSubClient@2.8
			LittleFS_esp32@1.0.5 TaskScheduler@3.6.0 Time@1.6.1 esp32-BG95@1.0.6 modem-freeRTOS@1.0.2
			sysfile@1.0.1 autorequest@1.0.1 alarm@1.0.1 modbusrtu@1.0.1
			"

if [ -f /.dockerenv ]; then
    echo "You are inside a Docker container!"
    docker="true"
fi

OS=$(uname -s)

running_os=""

case "$OS" in
  Linux)
    echo "You are on Linux!"
    running_os="linux"
    ;;
  Darwin)
    echo "You are on macOS!"
    running_os="macos"
    ;;
  *)
    echo "Unknown OS: $OS"
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--directory)
      home_dir="$2"
      echo "home dir set: ${home_dir}"
      shift 2
      ;;
    -p|--project)
      project="$2"
      echo "Project directory set: $project"
      shift 2
      ;;
    -a|--app)
      app_folder="$2"
      echo "app_folder set: $app_folder"
      shift 2
      ;;
    -m|--macro)
      app_macro="$2"
      echo "app_macro set: $app_macro"
      shift 2
      ;;
    -v|--app_version)
      app_version="$2"
      echo "app version set: $app_version"
      shift 2
      ;;
    --docker)
      docker=true
      echo "using docker env: $docker"
      shift 1
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

# Update system

if [ "$docker" == "true" ]; then
  running_os="linux"
	sudo apt-get update
  apt-get install -y git
fi

# Check if arduino-cli is installed
if command -v arduino-cli >/dev/null 2>&1; then
    echo "arduino-cli is installed."
else
    # Install arduino-cli
	curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh

	# Initialize arduino-cli (this will create default directories and config file)
	arduino-cli config init

	# Update the core index (required before installing cores or libraries)
	arduino-cli core update-index

	# Install ESP32 core
	arduino-cli core install esp32:esp32
fi

arduino_config_file="${home_dir}/.arduino15/arduino-cli.yaml"
arduino_lib_path="${home_dir}/Arduino/libraries/"

if [ "$docker" == "true" ]; then
	if grep -q "directories: libraries" $arduino_config_file; then
	    echo "The 'directories: libraries' entry exists in the file!"
	else
	    echo "The 'directories: libraries' entry does not exist in the file."
		# Add 'libraries' entry under 'directories'
		echo "Trying to fix it"
		if [ "$running_os" == "linux" ]; then
			sed -i "/directories:/a \ \ libraries: ${arduino_lib_path}" "$arduino_config_file"
		else
			echo "Os not supported to set it"
			exit 1
		fi
	fi
fi

arduino-cli config dump

# Install third-party libraries (replace 'LibraryName' with actual library names)

for lib in $libs; do
	echo $lib
	arduino-cli lib install $lib
done

if [ "$docker" == "true" ]; then
	ls "$arduino_lib_path"
  cd "$arduino_lib_path"
  if [ ! -d  "modem-freeRTOS" ]; then
    git clone https://github.com/zimbora/esp32-modem-freeRTOS.git
    mv esp32-modem-freeRTOS modem-freeRTOS
  fi
  if [ ! -d  "ESP32Logger2" ]; then
    git clone https://github.com/zimbora/ESP32Logger2.git
  fi
  cd /${project}
fi

echo "Installation complete!"
echo "project: ${project}"
echo "folder: ${app_folder}"
echo "app: ${app_macro}"

if [ -d "images/${app_folder}" ]; then
    rm -r "images/${app_folder}"
fi
mkdir -p images/${app_folder}

if [ "$docker" == "true" ]; then
  # removes soft links if any
  find src/app/ -type l -exec rm {} \;
fi

if [ "$running_os" == "macos" ]; then
  sed 's/#define APP_AUX_MACRO/#define APP_TEST/' package.h >> package_tmp.h
  rm package.h
  mv package_tmp.h package.h
elif [ "$running_os" == "linux" ]; then
  sed -i 's/#define APP_AUX_MACRO/#define APP_TEST/' package.h
fi

echo "Proceed to compilation"

arduino-cli cache clean

arduino-cli compile -b esp32:esp32:esp32 \
--build-property build.partitions=min_spiffs \
--build-property upload.maximum_size=1966080  \
--build-path ./build/${app_folder} . 2>&1 | tee compile_logs.txt


echo "Compilation done!"

#filenames=$( find build/${app_folder}/${project}* )
#cp ${filenames} images/${app_folder}/
cp build/${app_folder}/${project}.ino.bin images/${app_folder}/
cp build/${app_folder}/build.options.json images/${app_folder}/
echo "Files copied!"
