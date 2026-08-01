#
#  DYYY
#
#  Copyright (c) 2024 huami. All rights reserved.
#  Channel: @huamidev
#  Created on: 2024/10/04
#
# 本地配置文件（可选）
-include Makefile.local

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

#export THEOS=/Users/huami/theos
#export THEOS_PACKAGE_SCHEME=roothide

# 本地默认 rootless；SCHEME=rootful / SCHEME=roothide 可切换
SCHEME ?= rootless
ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
    export FINALPACKAGE = 1
else ifeq ($(SCHEME),rootful)
    unexport THEOS_PACKAGE_SCHEME
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
    export FINALPACKAGE = 1
else
    $(error Unknown SCHEME=$(SCHEME); use rootless, rootful, or roothide)
endif

# 在GitHub Actions中运行时的特殊配置
ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYYY

DYYY_FILES = DYYY.xm \
	DYYYFloatClearButton.xm \
	DYYYSettings.xm \
	DYYYABTestHook.xm \
	DYYYLongPressPanel.xm \
	Sources/Features/DYYYFloatSpeedButton.m \
	Sources/Settings/DYYYSettingsHelper.m \
	Sources/Settings/DYYYPickerDelegates.m \
	Sources/Media/DYYYBackupManager.m \
	Sources/Settings/DYYYSettingViewController.m \
	Sources/UI/DYYYKeyboardAvoidanceCoordinator.m \
	Sources/Features/DYYYLivePreStreamLayoutCoordinator.m \
	Sources/UI/DYYYBottomAlertView.m \
	Sources/UI/DYYYCustomInputView.m \
	Sources/UI/DYYYOptionsSelectionView.m \
	Sources/UI/DYYYIconOptionsDialogView.m \
	Sources/UI/DYYYAboutDialogView.m \
	Sources/UI/DYYYGlassConfirmView.m \
	Sources/UI/DYYYKeywordListView.m \
	Sources/UI/DYYYFilterSettingsView.m \
	Sources/UI/DYYYConfirmCloseView.m \
	Sources/UI/DYYYToast.m \
	Sources/Media/DYYYManager.m \
	Sources/Core/DYYYUtils.m \
	Sources/Features/DYYYLoginBypassManager.m \
	Sources/Features/DYYYPrivacyRecordUploadGuard.m \
	Sources/Core/CityManager.m \
	Sources/Core/AWMSafeDispatchTimer.m \
	Sources/Features/DYYYMiniProgramRewardBypass.m \
	Sources/Features/DYYYHideMusicButtonHooks.m \
	Sources/Features/DYYYHideMessageAndMinePageHooks.m \
	Sources/Features/DYYYHideKeyboardAIHooks.m
DYYY_CFLAGS = -fobjc-arc -w \
	-I$(THEOS_PROJECT_DIR)/Sources/Core \
	-I$(THEOS_PROJECT_DIR)/Sources/Settings \
	-I$(THEOS_PROJECT_DIR)/Sources/UI \
	-I$(THEOS_PROJECT_DIR)/Sources/Media \
	-I$(THEOS_PROJECT_DIR)/Sources/Features
DYYY_LDFLAGS = -weak_framework AVFAudio -lcompression
DYYY_FRAMEWORKS = UIKit Foundation AVFoundation CoreAudio UniformTypeIdentifiers
CXXFLAGS += -std=c++11
CCFLAGS += -std=c++11
DYYY_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS=0
export ERROR_ON_WARNINGS=0
export LOGOS_DEFAULT_GENERATOR=internal

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(shell whoami),huami)
    THEOS_DEVICE_IP = 192.168.31.227
else
    THEOS_DEVICE_IP = 192.168.15.201
endif
THEOS_DEVICE_PORT = 22

# 清理 packages 目录
clean::
	@echo -e "\033[31m==>\033[0m Cleaning packages…"
	@rm -rf .theos packages

# 编译并自动安装
after-package::
	@echo -e "\033[32m==>\033[0m Packaging complete."
	@if [ "$(GITHUB_ACTIONS)" != "true" ] && [ "$(INSTALL)" = "1" ]; then \
        DEB_FILE=$$(ls -t packages/*.deb | head -1); \
        PACKAGE_NAME=$$(basename "$$DEB_FILE" | cut -d'_' -f1); \
        echo -e "\033[34m==>\033[0m Installing $$PACKAGE_NAME to device…"; \
        ssh root@$(THEOS_DEVICE_IP) "rm -rf /tmp/$${PACKAGE_NAME}.deb"; \
        scp "$$DEB_FILE" root@$(THEOS_DEVICE_IP):/tmp/$${PACKAGE_NAME}.deb; \
        ssh root@$(THEOS_DEVICE_IP) "dpkg -i --force-overwrite /tmp/$${PACKAGE_NAME}.deb && rm -f /tmp/$${PACKAGE_NAME}.deb"; \
	else \
        echo -e "\033[33m==>\033[0m Skipping installation (GitHub Actions environment or INSTALL!=1)"; \
	fi
