{ hostname, home, pkgs, ...}:
{
  enable = true;
  package = null;               # firefox is installed using homebrew

  # arkenfox = {
  #   enable = false;
  #   version = "133.0";
  # };

  policies = {
    DisableTelemetry = true;
    DisableFirefoxStudies = true;
    EnableTrackingProtection = {
      Value =  true;
      Locked = true;
      Cryptomining = true;
      Fingerprinting = true;
    };
    DefaultDownloadDirectory = "${home}/Downloads";
    DisablePocket = true;
    DisableFirefoxScreenshots = true;
    OverrideFirstRunPage = "";
    OverridePostUpdatePage = "";
    DontCheckDefaultBrowser = true;
    DisplayBookmarksToolbar = "never";
    DisplayMenuBar = "never";
    SearchBar = "unified";
  };

  profiles = pkgs.lib.optionalAttrs (hostname == "hera") {
    "3xz6u5ly.default-release" = {
      id = 0;
      name = "default-release";
      isDefault = true;
      # arkenfox.enable = false;
    };

    "3ltwg757.default" = {
      id = 1;
      name = "default";
      # arkenfox.enable = false;
    };
  } // pkgs.lib.optionalAttrs (hostname == "clio") {
    "unj6oien.default-release" = {
      id = 0;
      name = "default-release";
      isDefault = true;
      # arkenfox.enable = false;
    };

    "v7m0m1sc.default" = {
      id = 1;
      name = "default";
      # arkenfox.enable = false;
    };
  } // {
    johnw = {
      id = 2;
      name = "John Wiegley";
      isDefault = hostname == "athena";
      # arkenfox.enable = false;
      extraConfig = ''
         user_pref("extensions.autoDisableScopes", 0);
         user_pref("extensions.enabledScopes", 15);
      '';
      containers = {
        "Kadena" = {
          id = 2;
          color = "red";
          icon = "chill";
        };
        "Assembly" = {
          id = 6;
          color = "green";
          icon = "fence";
        };
        "Copper to Gold" = {
          id = 7;
          color = "orange";
          icon = "circle";
        };
        "Banking" = {
          id = 3;
          color = "green";
          icon = "dollar";
        };
        "Shopping" = {
          id = 4;
          color = "pink";
          icon = "cart";
        };
        "Social Media" = {
          id = 9;
          color = "purple";
          icon = "fingerprint";
        };
      };

      userChrome = ''
        /* Hides tabs toolbar - OSX only */

        :root{ --uc-toolbar-height: 32px; }
        :root:not([uidensity="compact"]){ --uc-toolbar-height: 34px }

        #TabsToolbar > *{ visibility: collapse !important }
        #TabsToolbar > .titlebar-buttonbox-container{
        visibility: visible !important;
        height:var(--uc-toolbar-height) !important;
        }

        #nav-bar{
        margin-top: calc(0px - var(--uc-toolbar-height));
        }
        :root[inFullscreen] #navigator-toolbox{ margin-top: 11px }
      '';

      settings = {
        "accessibility.typeaheadfind.flashBar" = 0;
        "app.shield.optoutstudies.enabled" = false;
        "app.update.auto" = false;
        "browser.aboutConfig.showWarning" = false;
        "browser.aboutwelcome.didSeeFinalScreen" = true;
        "browser.contentblocking.category" = "strict";
        "browser.ctrlTab.sortByRecentlyUsed" = true;
        "browser.download.autohideButton" = false;
        "browser.download.lastDir" = "/Users/johnw/Downloads";
        "browser.download.panel.shown" = true;
        "browser.newtabpage.enabled" = false;
        "browser.search.region" = "US";
        "browser.search.update" = false;
        "browser.urlbar.showSearchSuggestionsFirst" = false;
        "browser.warnOnQuitShortcut" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.usage.uploadEnabled" = false;
        "doh-rollout.disable-heuristics" = true;
        "doh-rollout.home-region" = "US";
        "dom.disable_open_during_load" = false;
        "dom.forms.autocomplete.formautofill" = true;
        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_ever_enabled" = true;
        "extensions.autoDisableScopes" = 0;
        "font.name.serif.x-western" = "Bookerly";
        "identity.fxaccounts.account.device.name" = "Hera";
        "network.dns.disablePrefetch" = true;
        "network.http.speculative-parallel-limit" = 0;
        "network.predictor.enabled" = false;
        "network.prefetch-next" = false;
        "privacy.bounceTrackingProtection.mode" = 1;
        "privacy.donottrackheader.enabled" = true;
        "privacy.fingerprintingProtection" = true;
        "privacy.globalprivacycontrol.enabled" = true;
        "privacy.globalprivacycontrol.was_ever_enabled" = true;
        "privacy.query_stripping.enabled" = true;
        "privacy.query_stripping.enabled.pbmode" = true;
        "privacy.trackingprotection.emailtracking.enabled" = true;
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;
        "services.sync.syncInterval" = 600000;
        "services.sync.syncThreshold" = 300;
        "services.sync.username" = "jwiegley@gmail.com";
        "sidebar.visibility" = "hide-sidebar";
        "signon.rememberSignons" = false;
        "spellchecker.dictionary" = "en-US";
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.reportingpolicy.firstRun" = false;
        "trailhead.firstrun.didSeeAboutWelcome" = true;

        # browser.uiCustomization.state = {
        #   "placements" = {
        #     "widget-overflow-fixed-list" = [];
        #     "unified-extensions-area" = [
        #       "_a658a273-612e-489e-b4f1-5344e672f4f5_-browser-action"
        #       "_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action"
        #       "_3c078156-979c-498b-8990-85f7987dd929_-browser-action"
        #       "_c2c003ee-bd69-42a2-b0e9-6f34222cb046_-browser-action"
        #       "_a138007c-5ff6-4d10-83d9-0afaf0efbe5e_-browser-action"
        #       "_6003eac6-4b07-4aaf-960b-92fa006cd444_-browser-action"
        #       "openmultipleurls_ustat_de-browser-action"
        #       "jid1-bofifl9vbdl2zq_jetpack-browser-action"
        #       "_59e590fc-6635-45fe-89c7-af637eb4b9c0_-browser-action"
        #       "jid1-kkzogwgsw3ao4q_jetpack-browser-action"
        #     ];
        #     "nav-bar" = [
        #       "back-button"
        #       "forward-button"
        #       "stop-reload-button"
        #       "customizableui-special-spring1"
        #       "vertical-spacer"
        #       "urlbar-container"
        #       "_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action"
        #       "umatrix_raymondhill_net-browser-action"
        #       "ublock0_raymondhill_net-browser-action"
        #       "_154cddeb-4c8b-4627-a478-c7e5b427ffdf_-browser-action"
        #       "cookieautodelete_kennydo_com-browser-action"
        #       "_74145f27-f039-47ce-a470-a662b129930a_-browser-action"
        #       "_531906d3-e22f-4a6c-a102-8057b88a1a63_-browser-action"
        #       "zotero_chnm_gmu_edu-browser-action"
        #       "_ddc359d1-844a-42a7-9aa1-88a850a938a8_-browser-action"
        #       "_e2488817-3d73-4013-850d-b66c5e42d505_-browser-action"
        #       "_d07ccf11-c0cd-4938-a265-2a4d6ad01189_-browser-action"
        #       "_b9db16a4-6edc-47ec-a1f4-b86292ed211d_-browser-action"
        #       "unified-extensions-button"
        #       "_testpilot-containers-browser-action"
        #     ];
        #     "TabsToolbar" = [
        #       "firefox-view-button"
        #       "tabbrowser-tabs"
        #       "new-tab-button"
        #       "alltabs-button"
        #     ];
        #     "vertical-tabs" = [];
        #     "PersonalToolbar" = [
        #       "import-button"
        #       "personal-bookmarks"
        #     ];
        #   };
        #   "seen" = [
        #     "save-to-pocket-button"
        #     "developer-button"
        #     "_154cddeb-4c8b-4627-a478-c7e5b427ffdf_-browser-action"
        #     "_d07ccf11-c0cd-4938-a265-2a4d6ad01189_-browser-action"
        #     "_e2488817-3d73-4013-850d-b66c5e42d505_-browser-action"
        #     "_ddc359d1-844a-42a7-9aa1-88a850a938a8_-browser-action"
        #     "_c2c003ee-bd69-42a2-b0e9-6f34222cb046_-browser-action"
        #     "_a658a273-612e-489e-b4f1-5344e672f4f5_-browser-action"
        #     "_a138007c-5ff6-4d10-83d9-0afaf0efbe5e_-browser-action"
        #     "umatrix_raymondhill_net-browser-action"
        #     "_3c078156-979c-498b-8990-85f7987dd929_-browser-action"
        #     "_6003eac6-4b07-4aaf-960b-92fa006cd444_-browser-action"
        #     "_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action"
        #     "openmultipleurls_ustat_de-browser-action"
        #     "_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action"
        #     "cookieautodelete_kennydo_com-browser-action"
        #     "ublock0_raymondhill_net-browser-action"
        #     "jid1-bofifl9vbdl2zq_jetpack-browser-action"
        #     "_74145f27-f039-47ce-a470-a662b129930a_-browser-action"
        #     "_59e590fc-6635-45fe-89c7-af637eb4b9c0_-browser-action"
        #     "jid1-kkzogwgsw3ao4q_jetpack-browser-action"
        #     "_b9db16a4-6edc-47ec-a1f4-b86292ed211d_-browser-action"
        #     "zotero_chnm_gmu_edu-browser-action"
        #     "_531906d3-e22f-4a6c-a102-8057b88a1a63_-browser-action"
        #     "_testpilot-containers-browser-action"
        #   ];
        #   "dirtyAreaCache" = [
        #     "nav-bar"
        #     "vertical-tabs"
        #     "PersonalToolbar"
        #     "unified-extensions-area"
        #     "TabsToolbar"
        #     "widget-overflow-fixed-list"
        #   ];
        #   "currentVersion" = 21;
        #   "newElementCount" = 7;
        # };
      };

      search = {
        force = true;
        default = "google";
        order = [ "google" ];
        engines = {
          google.metaData.alias = "@g";
        };
      };
      extensions = {
        force = true;
        packages = with pkgs.nur.repos.rycee.firefox-addons; [
          aria2-integration
          auto-tab-discard
          cookie-autodelete
          copy-as-org-mode
          history-cleaner
          onepassword-password-manager
          org-capture
          sidebery
          single-file
          skip-redirect
          ublock-origin
          video-downloadhelper
          # vimium
          tridactyl

          # augmented-steam
          # bookmarks-organizer
          # choosy
          # colorzilla
          # dark-reader
          # downthemall
          # edit-with-emacs
          # font-finder
          # foxytab
          # imagus
          # multi-account-containers
          # native-mathml
          # open-multiple-urls
          # orbit
          # reddit-enhancement-suite
          # simple-translate
          # stylus
          # web-archives
          # web-developer
          # zotero-connector

          ## Not needed with uBlock Origin in medium mode
          # clearurls
          # decentraleyes
          # i-dont-care-about-cookies
          # popupoff
          # umatrix
        ];

        # Addon IDs can be found in about:support#addons
        settings = with pkgs.nur.repos.rycee.firefox-addons; {
          "${aria2-integration.addonId}".settings = {};

          "${auto-tab-discard.addonId}".settings = {
            audio = true;
            battery = false;
            click = "click.popup";
            faqs = false;
            favicon = false;
            favicon-delay = 500;
            "force.hostnames" = [];
            form = true;
            go-hidden = false;
            idle = true;
            idle-timeout = 300;
            "link.context" = true;
            log = false;
            "max.single.discard" = 50;
            memory-enabled = false;
            memory-value = 60;
            mode = "time-based";
            "notification.permission" = false;
            number = 0;
            online = true;
            "page.context" = true;
            paused = false;
            period = 600;
            pinned = false;
            prepends = "💤";
            simultaneous-jobs = 10;
            startup-pinned = true;
            startup-release-pinned = false;
            startup-unpinned = true;
            "tab.context" = true;
            "trash.period" = 24;
            "trash.unloaded" = false;
            "trash.whitelist-url" = [];
            whitelist = [
              "app.slack.com"
            ];
            whitelist-url = [];
          };

          "${cookie-autodelete.addonId}".settings = {
            settings =
            [
              {
                name = "activeMode";
                value = true;
              }
              {
                name = "cacheCleanup";
                value = true;
              }
              {
                name = "cleanCookiesFromOpenTabsOnStartup";
                value = true;
              }
              {
                name = "cleanExpiredCookies";
                value = true;
              }
              {
                name = "contextMenus";
                value = true;
              }
              {
                name = "contextualIdentities";
                value = true;
              }
              {
                name = "contextualIdentitiesAutoRemove";
                value = true;
              }
              {
                name = "debugMode";
                value = false;
              }
              {
                name = "delayBeforeClean";
                value = 15;
              }
              {
                name = "discardedCleanup";
                value = true;
              }
              {
                name = "domainChangeCleanup";
                value = true;
              }
              {
                name = "enableGreyListCleanup";
                value = true;
              }
              {
                name = "enableNewVersionPopup";
                value = false;
              }
              {
                name = "indexedDBCleanup";
                value = true;
              }
              {
                name = "keepDefaultIcon";
                value = false;
              }
              {
                name = "localStorageCleanup";
                value = true;
              }
              {
                name = "manualNotifications";
                value = true;
              }
              {
                name = "notificationOnScreen";
                value = 3;
              }
              {
                name = "pluginDataCleanup";
                value = true;
              }
              {
                name = "serviceWorkersCleanup";
                value = true;
              }
              {
                name = "showNotificationAfterCleanup";
                value = false;
              }
              {
                name = "showNumOfCookiesInIcon";
                value = true;
              }
              {
                name = "siteDataEmptyOnEnable";
                value = true;
              }
              {
                name = "sizePopup";
                value = 16;
              }
              {
                name = "sizeSetting";
                value = 16;
              }
              {
                name = "statLogging";
                value = true;
              }
            ];
          };

          "${copy-as-org-mode.addonId}".settings = {};

          "${history-cleaner.addonId}".settings = {};

          "${onepassword-password-manager.addonId}".settings = {};

          "${org-capture.addonId}".settings = {};

          "${sidebery.addonId}".settings = {};

          "${single-file.addonId}".settings = {};

          "${skip-redirect.addonId}".settings = {};

          "${ublock-origin.addonId}".settings = {
            userSettings = {
              advancedUserEnabled = true;
              cloudStorageEnabled = false;
              collapseBlocked = false;
              uiAccentCustom = true;
              uiAccentCustom0 = "#ACA0F7";
              externalLists = ''
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/anti.piracy.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/dyndns.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/fake.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/gambling.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/hoster.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt
                https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/ultimate.txt
              '';
              importedLists = [
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/anti.piracy.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/dyndns.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/fake.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/gambling.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/hoster.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/ultimate.txt"
              ];
              largeMediaSize = 250;
              popupPanelSections = 31;
              tooltipsDisabled = true;
            };
            hiddenSettings = {};
            dynamicFilteringString = ''
              behind-the-scene * * noop
              behind-the-scene * inline-script noop
              behind-the-scene * 1p-script noop
              behind-the-scene * 3p-script noop
              behind-the-scene * 3p-frame noop
              behind-the-scene * image noop
              behind-the-scene * 3p noop
              * * 3p-script block
              * * 3p-frame block
              old.reddit.com * 3p noop
              github.com * 3p-script noop
              github.com * 3p-frame noop
              github.com * 3p noop
              app.slack.com * 3p-script noop
              app.slack.com * 3p-frame noop
              app.slack.com * 3p noop
              respected-meat-54f.notion.site * 3p noop
              notebooklm.google.com * 3p-script noop
              notebooklm.google.com * 3p-frame noop
              notebooklm.google.com * 3p noop
              www.amazon.com * 3p noop
              www.linkedin.com * 3p noop
              www.facebook.com * 3p-script noop
              www.facebook.com * 3p-frame noop
              www.facebook.com * 3p noop
              drive.google.com * 3p noop
              www.reddit.com * 3p-script noop
              www.reddit.com * 3p-frame noop
              www.reddit.com * 3p noop
              www.tripit.com * 3p noop
            '';
            urlFilteringString = "";
            hostnameSwitchesString = ''
              no-remote-fonts: * true
              no-large-media: * true
              no-csp-reports: * true
              no-remote-fonts: www.ftb.ca.gov false
              no-large-media: www.ftb.ca.gov false
              no-remote-fonts: app.slack.com false
              no-remote-fonts: notebooklm.google.com false
            '';
            userFilters = "";
            selectedFilterLists = [
              "user-filters"
              "ublock-filters"
              "ublock-badware"
              "ublock-privacy"
              "ublock-quick-fixes"
              "ublock-unbreak"
              "easylist"
              "adguard-generic"
              "adguard-mobile"
              "easyprivacy"
              "adguard-spyware"
              "adguard-spyware-url"
              "block-lan"
              "urlhaus-1"
              "curben-phishing"
              "plowe-0"
              "dpollock-0"
              "fanboy-cookiemonster"
              "ublock-cookies-easylist"
              "adguard-cookies"
              "ublock-cookies-adguard"
              "fanboy-social"
              "adguard-social"
              "fanboy-thirdparty_social"
              "easylist-chat"
              "easylist-newsletters"
              "easylist-notifications"
              "easylist-annoyances"
              "adguard-mobile-app-banners"
              "adguard-other-annoyances"
              "adguard-popup-overlays"
              "adguard-widgets"
              "ublock-annoyances"
              "IRN-0"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/anti.piracy.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/hoster.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/dyndns.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/fake.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/gambling.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/ultimate.txt"
            ];
            whitelist = [
              "chrome-extension-scheme"
              "moz-extension-scheme"
            ];
          };

          "${video-downloadhelper.addonId}".settings = {};

          # "${vimium.addonId}".settings = {};

          "${tridactyl.addonId}".settings = {};
        };
      };
    };
  };
}
