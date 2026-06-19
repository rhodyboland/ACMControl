#include <Wire.h>
#include <Adafruit_MCP23X17.h>
#include <SPI.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>

#include "driver/twai.h"          // ESP-IDF TWAI driver (built-in)

/* ── CAN IDs (11-bit) ─────────────────────────────────────────────────── */
constexpr uint32_t ID_HB_ACM              = 0x181;
constexpr uint32_t ID_ACM_POWER_STATUS    = 0x100;
constexpr uint32_t ID_ACM_SOLAR_STATE     = 0x101;
constexpr uint32_t ID_ACM_CELL_INFO       = 0x102;
constexpr uint32_t ID_ACM_SENSOR_TEMPS    = 0x103;
/*  Output-status frames (optional—send them if you want the LCD LED icons) */
constexpr uint32_t ID_ACM_LC_STATE_1_4    = 0x110;
constexpr uint32_t ID_ACM_LC_STATE_5_8    = 0x111;
constexpr uint32_t ID_ACM_MC_STATE        = 0x120;
/*  Command frames coming *from* LCD  */
constexpr uint32_t ID_CMD_LC_SWITCH       = 0x200;
constexpr uint32_t ID_CMD_MC_SWITCH       = 0x201;
constexpr uint32_t ID_CMD_LC_BRIGHTNESS   = 0x202;
constexpr uint32_t ID_CMD_INV_SWITCH      = 0x203;

// --- Feature / Protocol flags coming from app ---
enum BatteryProtocol_t { BP_NONE, BP_JK, BP_BMV };
enum SolarProtocol_t   { SP_NONE, SP_VIC };

bool featureBmsEnabled   = true;          // FB
BatteryProtocol_t bmsProto = BP_NONE;     // BP: NONE / JK / BMV
bool featureSolarEnabled = true;          // FS
SolarProtocol_t   solarProto = SP_VIC;    // SP: NONE / VIC

constexpr uint16_t CONFIG_VERSION = 1;
const char* CONFIG_NAMESPACE = "acm_cfg";

// Serial1 can be either Solar MPPT or BMV shunt depending on config
enum Serial1Mode_t { SERIAL1_NONE, SERIAL1_SOLAR, SERIAL1_BMV };
Serial1Mode_t serial1Mode = SERIAL1_SOLAR;

// Separate “connection active” flags for clarity
bool solarVedirectActive = false;  // MPPT on VE.Direct
bool bmvVedirectActive   = false;  // BMV on VE.Direct

#pragma once

#define ACM_HW_REV 2   // set to 2 or 3

#if (ACM_HW_REV != 2) && (ACM_HW_REV != 3)
#error "ACM_HW_REV must be 2 or 3"
#endif

// ----- Constants and Definitions -----
#define RGB_BRIGHTNESS 255
#define V_SENSE 2
#define thermisterSeriesRes 9880

// ----- ESP32 OUTPUTS -----
#if ACM_HW_REV == 3
  #define LC5 17
  #define LC6 18
  #define LC7 19
  #define LC8 38
  #define LC1 39
  #define LC2 40
  #define LC3 41
  #define LC4 42
  #define MC1 45
  #define MC2 16
#elif ACM_HW_REV == 2
  #define LC1 17
  #define LC2 18
  #define LC3 19
  #define LC4 35
  #define LC5 36
  #define LC6 37
  #define LC7 38
  #define LC8 39
  #define MC1 40
  #define MC2 41
#endif

// ----- SPI IO-Expander MCP23S17 OUTPUTS -----
#define MCP_ChipSelect 10
#define Q1_SEn 0
#define Q1_SEL0 1
#define Q1_SEL1 2
#define Q1_RST 3

#if ACM_HW_REV == 3
  #define Q2_SEn 0
  #define Q2_SEL0 1
  #define Q2_SEL1 2
  #define Q2_RST 4
  #define D_SEn 5
  #define D_SEL 6
  #define D_RST 7
#elif ACM_HW_REV == 2
  #define Q2_SEn 4
  #define Q2_SEL0 5
  #define Q2_SEL1 6
  #define Q2_RST 7
  #define D_SEn 8
  #define D_SEL 9
  #define D_RST 10
#endif

#define INV_CTRL 15

// ----- ESP32 INPUTS -----
#define INV_STATE 1
#define Q1_CS 3
#define Q2_CS 4
#define D_CS 5
#define SENSE_1 6
#define SENSE_2 7

#if ACM_HW_REV == 3
  #define EXT_SW1 14
  #define EXT_SW2 15
#elif ACM_HW_REV == 2
  #define EXT_SW1 42
  #define EXT_SW2 45
  #define SPARE1 14
  #define SPARE2 15
  #define SPARE3 16
#endif

// USART 1 5V (Victron)
#define U1_RX 8
#define U1_TX 9

// USART 2 3v3 (JK BMS)
#define U2_RX 46
#define U2_TX 47

// CAN SN65HVD230DR
#define CAN_TX 20
#define CAN_RX 21

// MCP23S17 Setup
Adafruit_MCP23X17 mcp;

// ----- BLE Definitions -----
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define ACM_SERIAL_NUMBER   "ACM-0001"

BLECharacteristic *pCharacteristic;
String bleDeviceName;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Configuration and Status Variables
float critVoltage = 10.0;
float cutOutVoltage = 11.0;
float cutInVoltage = 11.5;
bool autoCutoffEnabled = true;
bool alwaysOnChannels[10] = {false, false, false, false, false, false, false, false, false, false};
bool priorityChannels[10] = {false, false, false, false, false, false, false, false, false, false}; // Priority channels
bool lowCurrentStates[8] = {false, false, false, false, false, false, false, false};
bool mediumCurrentStates[2] = {false, false};
int lowCurrentBrightness[8] = {255, 255, 255, 255, 255, 255, 255, 255};

// Voltage divider ratio and calibration factor for voltage sensing
const float voltageDividerRatio = 5.68;
const float voltageCalibrationFactor = 1.021;

// Rolling average buffer for voltage readings
const int voltageBufferSize = 10;
float voltageBuffer[voltageBufferSize] = {0.0};
int voltageBufferIndex = 0;
unsigned long lastVoltageReadMillis = 0; // Last voltage read timestamp

const int currentBufferSize = 10; // Rolling average size for current values

// Buffers to store last 10 current readings for each channel
float lowCurrentBuffers[8][currentBufferSize] = {0};
int lowCurrentIndex[8] = {0};

// Buffers to store last 10 current readings for each medium current channel
float mediumCurrentBuffers[2][currentBufferSize] = {0};
int mediumCurrentIndex[2] = {0};

bool errorPresent = false;
int errorCode = 0;
bool outputsDisabled = false;
float batteryVoltage = 0; // This is the main voltage we feed into the system
float totalCurrent = 0;

float sensor1 = 0;

// Maximum block size to prevent buffer overflow
#define MAX_BLOCK_SIZE 512

// Buffer to store incoming block data
char blockBuffer[MAX_BLOCK_SIZE];
int blockIndex = 0;

// Watchdog variables (for Victron)
unsigned long lastSerialDataMillis = 0; 
const unsigned long WATCHDOG_TIMEOUT = 3000; 
bool serialConnectionActive = false; // Flag for Victron connection

// ----- Victron Fields -----
unsigned int PID; // Product ID
unsigned int FW;  // Firmware version
String SER_num;   // Serial number
int V;            // main battery voltage
int I;            // main battery current
int VPV;          // panel voltage (mV)
int PPV;          // Panel Power (W)
int CS;           // Current state (of operation)
unsigned long OR; // Off reason
int ERR;          // Error code
String LOAD_state;// Load state (ON/OFF)
int IL;           // Load Current (mA)
int H19;          // Yield total (0.01kWh)
int H20;          // Yield today (0.01kWh)
int H21;          // Max power today (W)
int H22;          // Yield Yesterday (0.01kWh)
int H23;          //Max power yesterday (W)
int HSDS;         // Day sequence number (0-364)
int TTG_min;
int CE_mAh;
int SOC_BMV;

int V_mV = 0;
int I_mA = 0;
int T_cdec = 0; // BMV T is °C*10 (per docs variants) but list shows "°C8"; we’ll treat as raw °C.
int P_W = 0;

// Enum to manage reading states
enum State { 
  READING_LINES,
  BLOCK_COMPLETE
};
State currentState = READING_LINES;

// Temporary storage for the current line being read
String currentLine = "";
uint32_t checksumSum = 0;

// ----------------------------------------------------------------------
// JK-BMS Integration
// ----------------------------------------------------------------------
HardwareSerial SerialBMS(2);  // Use UART #2 on ESP32-S3

// Full request frame for JK-BMS:
static const uint8_t JK_BMS_REQUEST[] = {
  0x4E, 0x57, 0x00, 0x13, 0x00, 0x00, 0x00, 0x00,
  0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x68, 0x00, 0x00, 0x01, 0x29
};

// We read up to 512 bytes from BMS
uint8_t bmsBuf[512];
uint16_t bmsLen = 0;
unsigned long lastBmsDataMillis = 0;
bool bmsConnected = false; // Flag for BMS connection

// BMS data
float bmsVoltage = -1.0f;
float bmsCurrent = 0.0f;
float bmsPower   = 0.0f;
uint8_t bmsSoc   = 0;
// We parse up to 4 cells for demonstration
float cellVoltages[4] = {0,0,0,0};
float avgCellVoltage   = 0.0f;
int16_t mosTemp        = -999;
int16_t batTemp1       = -999;
int16_t batTemp2       = -999;

// ── CAN timing buckets ───────────────────────────────────────────────────
static uint32_t tLastHb      = 0;
static uint32_t tLast10Hz    = 0;
static uint32_t tLast2Hz     = 0;
static uint32_t tLast1Hz     = 0;


// Helper: read for up to `timeoutMs` from BMS
uint16_t readBmsFrame(uint16_t timeoutMs) {
  uint16_t idx = 0;
  unsigned long start = millis();
  while (millis() - start < timeoutMs) {
    while (SerialBMS.available()) {
      if (idx < 512) {
        bmsBuf[idx++] = SerialBMS.read();
      } else {
        // overflow discard
        SerialBMS.read();
      }
      start = millis(); // reset timeout
    }
  }
  return idx;
}

void reconfigureSerial1Mode()
{
  // If BMV chosen for battery, VE.Direct port must be reserved for BMV.
  if (featureBmsEnabled && bmsProto == BP_BMV) {
    serial1Mode = SERIAL1_BMV;
    // App UX already disables Solar when BMV selected, mirror that here:
    featureSolarEnabled = false;
    solarProto = SP_NONE;

    // Clear solar readings so BLE/ CAN don’t show stale solar values
    VPV = 0; PPV = 0; CS = 0; I = 0;
    solarVedirectActive = false;
  } else if (featureSolarEnabled && solarProto == SP_VIC) {
    serial1Mode = SERIAL1_SOLAR;
  } else {
    serial1Mode = SERIAL1_NONE;
    solarVedirectActive = false;
  }

  // Also decide if we should poll the JK-BMS
  // (only when JK selected; BMV uses VE.Direct, not Serial2)
  bmsConnected = false;  // will be set true by the active data path
}


// Read a 16-bit big-endian integer from buf[offset..offset+1]
uint16_t readU16BE(const uint8_t *buf) {
  return (uint16_t(buf[0]) << 8) | buf[1];
}

// Convert JK “raw temperature” to signed degrees C
int16_t convertJKTemperature(uint16_t rawVal) {
  if (rawVal <= 100) return rawVal;
  return rawVal - 200; 
}

// Current: top bit => charge vs discharge, rest => x0.1A
float convertJKCurrent(uint16_t rawValBE) {
  bool isCharge = (rawValBE & 0x8000) != 0;
  uint16_t magnitude = (rawValBE & 0x7FFF);
  float amps = magnitude * 0.01f;
  return isCharge ? amps : -amps;
}

bool parseBmsFrame(const uint8_t *buf, uint16_t len) {
  if (len < 10) return false;
  if (buf[0] != 0x4E || buf[1] != 0x57) return false;
  // For demonstration, parse these tokens: 0x79 (cells), 0x80..82 temps, 0x83 volt, 0x84 current, 0x85 SOC
  // We'll reset them each parse:
  for (int c = 0; c < 4; c++) cellVoltages[c] = 0.0f;
  avgCellVoltage = 0.0f;
  bmsVoltage = -1.0f;
  bmsCurrent = 0.0f;
  bmsPower   = 0.0f;
  bmsSoc     = 0;
  mosTemp    = -999;
  batTemp1   = -999;
  batTemp2   = -999;

  uint16_t i = 0;
  while (i + 1 < len) {
    uint8_t token = buf[i];
    if (token == 0x79 && i + 1 < len) {
      uint8_t blockSize = buf[i+1];
      uint16_t needed = i + 2 + blockSize;
      if (needed > len) break;

      uint8_t cellCount = blockSize / 3; 
      float sumC = 0.0f;
      for (uint8_t c=0; c<cellCount && c<4; c++) {
        uint16_t off = i + 2 + c*3;
        // [cellIndex, hiVolt, loVolt]
        uint16_t mv = (buf[off+1]<<8) | buf[off+2];
        float cv = mv * 0.001f;
        cellVoltages[c] = cv;
        sumC += cv;
      }
      if (cellCount > 0) {
        avgCellVoltage = sumC / cellCount;
      }
      i = needed;
    }
    else if (token == 0x80 && i+2 < len) {
      uint16_t rawT = readU16BE(&buf[i+1]);
      mosTemp = convertJKTemperature(rawT);
      i += 3;
    }
    else if (token == 0x81 && i+2 < len) {
      uint16_t rawT = readU16BE(&buf[i+1]);
      batTemp1 = convertJKTemperature(rawT);
      i += 3;
    }
    else if (token == 0x82 && i+2 < len) {
      uint16_t rawT = readU16BE(&buf[i+1]);
      batTemp2 = convertJKTemperature(rawT);
      i += 3;
    }
    else if (token == 0x83 && i+2 < len) {
      uint16_t raw10mV = readU16BE(&buf[i+1]);
      bmsVoltage = raw10mV * 0.01f;
      i += 3;
    }
    else if (token == 0x84 && i+2 < len) {
      uint16_t rawCur = readU16BE(&buf[i+1]);
      bmsCurrent = convertJKCurrent(rawCur);
      i += 3;
    }
    else if (token == 0x85 && i+1 < len) {
      bmsSoc = buf[i+1];
      i += 2;
    }
    else {
      i++;
    }
  }

  bmsPower = bmsVoltage * bmsCurrent;

  // Mark success if we at least have a voltage > 0
  if (bmsVoltage > 0.0f) {
    return true;
  }
  return false;
}

float readInverterVoltage() {
    // Example: If INV_STATE is an analog-capable pin
    // Adjust the ADC range, voltage reference, and scaling as needed
    int rawValue = analogRead(INV_STATE);
    float measuredVoltage = (rawValue * 3.3f / 4095.0f); // For ESP32 12-bit ADC
    return measuredVoltage;
}

// Poll the JK-BMS, read & parse data
void pollBms() {
  // 1) Clear leftover
  while (SerialBMS.available()) {
    SerialBMS.read();
  }
  // 2) Send the full request
  SerialBMS.write(JK_BMS_REQUEST, sizeof(JK_BMS_REQUEST));
  // 3) Wait & read
  uint16_t length = readBmsFrame(1000); 
  if (length == 0) {
    // No data => possibly disconnected
    return;
  }
  if (parseBmsFrame(bmsBuf, length)) {
    bmsConnected = true;
    lastBmsDataMillis = millis();
  }
}



// ----------------------------------------------------------------------
// Function Prototypes from Original Code
// ----------------------------------------------------------------------
void setLEDColor(char color);
void flashLED(char color, int times, int delayTime);
void pulseLED(char color, int pulseDuration);
void handleAutoShutdownWarning();
void checkBatteryVoltage();
void handleConnectionIndicator();
void handleCommandReceivedIndicator();
void handleErrorIndicator(int errorCode);
void disableOutputs();
void manageErrorState();
float readRealVoltage();
void sendSensorData();
int getLowCurrentPin(int index);
int getMediumCurrentPin(int index);
float readQuadCurrent(int channel, int selectPin, int sensePin);
float readDualCurrent(int channel);
void applyConfiguration(const std::string &config);
void startBLEAdvertising();
void loadConfiguration();
void saveConfiguration();

uint16_t boolArrayToMask(const bool values[], int count) {
  uint16_t mask = 0;
  for (int i = 0; i < count; ++i) {
    if (values[i]) {
      mask |= (1 << i);
    }
  }
  return mask;
}

void maskToBoolArray(uint16_t mask, bool values[], int count) {
  for (int i = 0; i < count; ++i) {
    values[i] = (mask & (1 << i)) != 0;
  }
}

void loadConfiguration() {
  Preferences prefs;
  if (!prefs.begin(CONFIG_NAMESPACE, true)) {
    Serial.println("Failed to open config storage for reading; using defaults.");
    return;
  }

  uint16_t version = prefs.getUShort("version", 0);
  if (version != CONFIG_VERSION) {
    prefs.end();
    Serial.println("No compatible saved config found; using defaults.");
    return;
  }

  cutOutVoltage = prefs.getFloat("cut_out", cutOutVoltage);
  cutInVoltage = prefs.getFloat("cut_in", cutInVoltage);
  autoCutoffEnabled = prefs.getBool("auto_cut", autoCutoffEnabled);
  maskToBoolArray(prefs.getUShort("always_on", boolArrayToMask(alwaysOnChannels, 10)), alwaysOnChannels, 10);
  maskToBoolArray(prefs.getUShort("priority", boolArrayToMask(priorityChannels, 10)), priorityChannels, 10);
  featureBmsEnabled = prefs.getBool("bms_en", featureBmsEnabled);
  bmsProto = static_cast<BatteryProtocol_t>(prefs.getUChar("bms_proto", static_cast<uint8_t>(bmsProto)));
  if (bmsProto != BP_NONE && bmsProto != BP_JK && bmsProto != BP_BMV) {
    bmsProto = BP_NONE;
  }
  featureSolarEnabled = prefs.getBool("solar_en", featureSolarEnabled);
  solarProto = static_cast<SolarProtocol_t>(prefs.getUChar("solar_proto", static_cast<uint8_t>(solarProto)));
  if (solarProto != SP_NONE && solarProto != SP_VIC) {
    solarProto = SP_NONE;
  }
  prefs.end();

  reconfigureSerial1Mode();
  Serial.println("Loaded config from flash.");
}

void saveConfiguration() {
  Preferences prefs;
  if (!prefs.begin(CONFIG_NAMESPACE, false)) {
    Serial.println("Failed to open config storage for writing.");
    return;
  }

  prefs.putUShort("version", CONFIG_VERSION);
  prefs.putFloat("cut_out", cutOutVoltage);
  prefs.putFloat("cut_in", cutInVoltage);
  prefs.putBool("auto_cut", autoCutoffEnabled);
  prefs.putUShort("always_on", boolArrayToMask(alwaysOnChannels, 10));
  prefs.putUShort("priority", boolArrayToMask(priorityChannels, 10));
  prefs.putBool("bms_en", featureBmsEnabled);
  prefs.putUChar("bms_proto", static_cast<uint8_t>(bmsProto));
  prefs.putBool("solar_en", featureSolarEnabled);
  prefs.putUChar("solar_proto", static_cast<uint8_t>(solarProto));
  prefs.end();

  Serial.println("Saved config to flash.");
}

// ----------------------------------------------------------------------
// BLE Setup
// ----------------------------------------------------------------------
class MyCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        handleConnectionIndicator(); // New device connected
    }
    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        startBLEAdvertising();
        flashLED('R', 1, 250); // Device disconnected
    }
};

class CharacteristicCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = std::string(pCharacteristic->getValue().c_str());
        if (value.length() > 0) {
            Serial.print("Received command: ");
            Serial.println(value.c_str());
            handleCommandReceivedIndicator(); // Command received

            char command = value[0];
            switch (command) {
                case 'L': { 
                    int lcIndex = value[1] - '1';
                    lowCurrentStates[lcIndex] = (value[2] == '1');
                    digitalWrite(getLowCurrentPin(lcIndex + 1), lowCurrentStates[lcIndex] ? HIGH : LOW);
                    break;
                }
                case 'M': { 
                    int mcIndex = value[1] - '1';
                    mediumCurrentStates[mcIndex] = (value[2] == '1');
                    digitalWrite(getMediumCurrentPin(mcIndex + 1), mediumCurrentStates[mcIndex] ? HIGH : LOW);
                    break;
                }
                case 'B': { 
                    int lcIndex = value[1] - '1';
                    lowCurrentBrightness[lcIndex] = std::stoi(value.substr(2));
                    if (lowCurrentStates[lcIndex]) {
                        analogWrite(getLowCurrentPin(lcIndex + 1), lowCurrentBrightness[lcIndex]);
                    }
                    break;
                }
                case 'E': { 
                    int code = std::stoi(value.substr(1));
                    handleErrorIndicator(code);
                    break;
                }
                case 'C': { 
                    applyConfiguration(value);
                    break;
                }

                case 'I': {

                    // Example command: "I1X" => 'I' + "1" for inverter #1 + "1" or "0" for ON/OFF
                    // If you only have one inverter channel, you can ignore the second char or just assume index = 1
                    int invIndex = value[1] - '1'; 
                    bool turnOn  = (value[2] == '1');
                    // For an inverter that toggles on momentary press, we do a short pulse on INV_CTRL:
                    Serial.print("Inverter command received: ");
                    Serial.println(turnOn ? "ON" : "OFF");

                    // Pulse the control pin—just do the same action for ON or OFF if the inverter toggles.
                    // Adjust timing if your inverter needs a shorter or longer pulse.
                    mcp.digitalWrite(INV_CTRL, HIGH);
                    delay(250);          // 250ms press
                    mcp.digitalWrite(INV_CTRL, LOW);
                    break;

                }
                default:
                    handleErrorIndicator(1); 
                    break;
            }
        }
    }
};


/**
 * @brief Update the channel outputs based on:
 *        - Always-On flags
 *        - Priority flags
 *        - Low battery conditions
 *        - User states (lowCurrentStates, mediumCurrentStates)
 */
void updateChannels() {
    // Decide logic thresholds:
    bool batteryIsCritical = autoCutoffEnabled && (batteryVoltage < critVoltage);
    bool batteryIsLow      = autoCutoffEnabled && (batteryVoltage < cutOutVoltage);

    // ----- LOW CURRENT CHANNELS (8 channels) -----
    for (int i = 0; i < 8; i++) {
        // Always-On channel or Priority channel?
        bool ao  = alwaysOnChannels[i];     // always on
        bool pri = priorityChannels[i];     // priority

        // If battery is critically low, turn everything off
        if (batteryIsCritical) {
            lowCurrentStates[i] = false;
            digitalWrite(getLowCurrentPin(i + 1), LOW);
        }
        // If battery is below normal cut-out but above critical:
        // - Keep Priority or Always-On channels ON
        else if (batteryIsLow) {
            if (ao || pri) {
                // Force ON
                lowCurrentStates[i] = true;
                digitalWrite(getLowCurrentPin(i + 1), HIGH);
            } else {
                // Force OFF for non-priority
                lowCurrentStates[i] = false;
                digitalWrite(getLowCurrentPin(i + 1), LOW);
            }
        }
        // Otherwise, battery is above cut-out => normal operation
        else {
            if (ao) {
                // Force ON if Always-On
                lowCurrentStates[i] = true;
                digitalWrite(getLowCurrentPin(i + 1), HIGH);
            } else {
                // Use whatever the user/app last commanded
                digitalWrite(getLowCurrentPin(i + 1), lowCurrentStates[i] ? HIGH : LOW);
            }
        }
    }

    // ----- MEDIUM CURRENT CHANNELS (2 channels) -----
    for (int i = 0; i < 2; i++) {
        // For medium channels, decide how you want alwaysOn/priority to behave.
        // If you have alwaysOn/priority settings for them, use the same approach.
        // For demonstration, let's assume the first 2 bits of each array apply to medium channels 0 and 1:
        bool ao  = alwaysOnChannels[8 + i];      // Channels 9 and 10 in your array
        bool pri = priorityChannels[8 + i];      // Channels 9 and 10 in your array

        if (batteryIsCritical) {
            mediumCurrentStates[i] = false;
            digitalWrite(getMediumCurrentPin(i + 1), LOW);
        }
        else if (batteryIsLow) {
            if (ao || pri) {
                mediumCurrentStates[i] = true;
                digitalWrite(getMediumCurrentPin(i + 1), HIGH);
            } else {
                mediumCurrentStates[i] = false;
                digitalWrite(getMediumCurrentPin(i + 1), LOW);
            }
        }
        else {
            if (ao) {
                mediumCurrentStates[i] = true;
                digitalWrite(getMediumCurrentPin(i + 1), HIGH);
            } else {
                digitalWrite(getMediumCurrentPin(i + 1), mediumCurrentStates[i] ? HIGH : LOW);
            }
        }
    }
}

void getSensor() {
  
  float reading = analogRead(SENSE_1);
 
  // Serial.print("Analog reading "); 
  // Serial.println(reading);
 
  // convert the value to resistance
  reading = (4095 / reading)  - 1;     // (1023/ADC - 1) 
  reading = thermisterSeriesRes / reading;  // 10K / (1023/ADC - 1)
  // Serial.print("Thermistor resistance "); 

  float steinhart;
  steinhart = reading / 9000;     // (R/Ro)
  steinhart = log(steinhart);                  // ln(R/Ro)
  steinhart /= 3950;                   // 1/B * ln(R/Ro)
  steinhart += 1.0 / (25 + 273.15); // + (1/To)
  steinhart = 1.0 / steinhart;                 // Invert
  steinhart -= 273.15; 
  // Serial.println(steinhart);
  sensor1 = steinhart;
}

// ----------------------------------------------------------------------
// Helper: parse the complete Victron block
// ----------------------------------------------------------------------
// Parses VE.Direct block when connected to a Victron MPPT (Solar)
void parseVEDirectBlockSolar(char* buffer)
{
  char tempBuffer[MAX_BLOCK_SIZE];
  strncpy(tempBuffer, buffer, MAX_BLOCK_SIZE);
  tempBuffer[MAX_BLOCK_SIZE - 1] = '\0';

  // Reset/keep only fields used for solar
  // V,I here are MPPT internal bus values; we already track battery via other path
  VPV = 0; PPV = 0; CS = 0; I = 0; ERR = 0;

  char* line = strtok(tempBuffer, "\r\n");
  while (line != NULL) {
    char* tabPos = strchr(line, '\t');
    if (tabPos) {
      *tabPos = '\0';
      const char* label = line;
      const char* value = tabPos + 1;

      if (strcmp(label, "VPV") == 0) {
        VPV = atoi(value);                 // mV
      } else if (strcmp(label, "PPV") == 0) {
        PPV = atoi(value);                 // W
      } else if (strcmp(label, "CS") == 0) {
        CS = atoi(value);                  // state enum
      } else if (strcmp(label, "I") == 0) {
        I  = atoi(value);                  // mA (can be negative)
      } else if (strcmp(label, "ERR") == 0) {
        ERR = atoi(value);
      }
    }
    line = strtok(NULL, "\r\n");
  }

  solarVedirectActive = true;
  bmvVedirectActive   = false;
    lastSerialDataMillis = millis();

}


// Parses VE.Direct block when connected to a Victron BMV (battery monitor)
// We map BMV fields into the same “BMS-like” globals used elsewhere.
void parseVEDirectBlockBMV(char* buffer)
{
  char tempBuffer[MAX_BLOCK_SIZE];
  strncpy(tempBuffer, buffer, MAX_BLOCK_SIZE);
  tempBuffer[MAX_BLOCK_SIZE - 1] = '\0';

  // Reset only what we overwrite; keep SOC if you later compute it

  char* line = strtok(tempBuffer, "\r\n");
  while (line != NULL) {
    char* tabPos = strchr(line, '\t');
    if (tabPos) {
      *tabPos = '\0';
      const char* label = line;
      const char* value = tabPos + 1;

      if (strcmp(label, "V") == 0) {             // mV main batt voltage
        V_mV = atoi(value);
      } else if (strcmp(label, "I") == 0) {      // mA, signed
        I_mA = atoi(value);
      } else if (strcmp(label, "T") == 0) {      // °C (some firmwares use deci-deg)
        T_cdec = atoi(value);
      } else if (strcmp(label, "P") == 0) {      // W
        P_W = atoi(value);
      } else if (strcmp(label, "TTG") == 0) {    // minutes
        TTG_min = atoi(value);
      }else if (strcmp(label, "CE") == 0) {    // mah
        CE_mAh = atoi(value);
      }else if (strcmp(label, "SOC") == 0) {    // mah
        SOC_BMV = atoi(value);
      }
      // (You can extend here for CE, H7/H8, etc., as needed)
    }
    line = strtok(NULL, "\r\n");
  }

  // Map into “BMS-style” globals the app already uses
  bmsVoltage = V_mV / 1000.0f;
  bmsCurrent = I_mA / 1000.0f;  // sign preserved
  bmsPower   = (float)P_W;
  batTemp1   = T_cdec;          // treat as °C; adjust scaling if you confirm deci-deg
    if (bmsSoc >= 0) {
        bmsSoc = SOC_BMV / 10.0f;
    }

  bmsConnected        = true;
  bmvVedirectActive   = true;
  solarVedirectActive = false;

  // When BMV is active, ensure solar telemetry (VPV/PPV/CS/I) doesn’t show stale
  VPV = 0; PPV = 0; CS = 0; I = 0;
    lastSerialDataMillis = millis();
    lastBmsDataMillis = millis();

}


/* Send a short CAN frame, blocking up to 10 ms if bus is busy */
static inline void canSend(uint32_t id, const uint8_t *data, uint8_t dlc)
{
    twai_message_t msg{};
    msg.identifier       = id;
    msg.data_length_code = dlc;
    msg.extd             = 0;
    memcpy(msg.data, data, dlc);
    twai_transmit(&msg, pdMS_TO_TICKS(10));
}

/* called once per second */
static void sendHeartbeat()
{
    uint8_t st = 0x01;           // “OK”
    canSend(ID_HB_ACM, &st, 1);
}

/* build-and-send the four telemetry frames */
static void sendTelemetry10Hz()     // 0x100   (runs every 100 ms)
{
    uint8_t d[8];
    //  batt V  & I
    
    uint16_t rawBV = (uint16_t)(batteryVoltage * 100);   // 0.01 V
    // new unsigned encoding with +512 A bias
    // scale = 0.01 A → offsetRaw = 512 A ÷ 0.01 A = 51200 units
    float batteryCurrentForTelemetry = bmsConnected ? bmsCurrent : totalCurrent;
    int32_t tmpBI = (int32_t)roundf(batteryCurrentForTelemetry * 100.0f) + 51200;
    uint16_t rawBIoff = (uint16_t)tmpBI;             // wrap if out of range


    /* VPV is in millivolts, I is in milliamps (can be negative)  */
    uint16_t rawSV = VPV / 10;            // 0.01-volt units
    int16_t  rawSI = I   / 10;            // 0.01-amp  units, signed


    d[0] = rawBV >> 8;  d[1] = rawBV & 0xFF;
    d[2] = rawBIoff >> 8; d[3] = rawBIoff & 0xFF;
    d[4] = rawSV >> 8;  d[5] = rawSV & 0xFF;
    d[6] = rawSI >> 8;  d[7] = rawSI & 0xFF;
    canSend(ID_ACM_POWER_STATUS, d, 8);
}

static void sendTelemetry2Hz()      // 0x103, maybe 0x110… (every 500 ms)
{
    /* Example: internal temp only */
    int16_t rawT = (int16_t)(sensor1 * 10);   // 0.1 °C
    uint8_t d[8] = { uint8_t(rawT>>8), uint8_t(rawT) };
    canSend(ID_ACM_SENSOR_TEMPS, d, 2);

   /* LC 1-4  ------------------------------------------------------------- */
uint8_t s14 = (lowCurrentStates[0]<<0)|(lowCurrentStates[1]<<1)|
              (lowCurrentStates[2]<<2)|(lowCurrentStates[3]<<3);
uint8_t d110[8] = { s14,
                    lowCurrentBrightness[0], lowCurrentBrightness[1],
                    lowCurrentBrightness[2], lowCurrentBrightness[3] };
canSend(ID_ACM_LC_STATE_1_4, d110, 5);

/* LC 5-8  ------------------------------------------------------------- */
uint8_t s58 = (lowCurrentStates[4]<<0)|(lowCurrentStates[5]<<1)|
              (lowCurrentStates[6]<<2)|(lowCurrentStates[7]<<3);
uint8_t d111[8] = { s58,
                    lowCurrentBrightness[4], lowCurrentBrightness[5],
                    lowCurrentBrightness[6], lowCurrentBrightness[7] };
canSend(ID_ACM_LC_STATE_5_8, d111, 5);

/* MC 1-2  ------------------------------------------------------------- */
uint8_t sMC = (mediumCurrentStates[0]<<0)|(mediumCurrentStates[1]<<1);
uint8_t d120[2] = { sMC };
canSend(ID_ACM_MC_STATE, d120, 1);

}

static void sendTelemetry1Hz()      // 0x101 / 0x102
{
    /* 0x101 – solar power + mode */
    uint16_t rawP = (uint16_t)(PPV);            // 1 W steps
    uint8_t  mode = CS;                         // whatever mapping you prefer
    uint8_t d101[8] = { rawP>>8, rawP, mode };
    canSend(ID_ACM_SOLAR_STATE, d101, 3);

    /* 0x102 – cell average, SOC, flags */
    uint16_t rawCell = (uint16_t)(avgCellVoltage * 100);   // 0.01 V
    uint8_t  soc     = bmsSoc;
    uint8_t  flags   = (bmsConnected        ? 0x02 : 0) |
                       (serialConnectionActive ? 0x01 : 0);
    uint8_t d102[8]  = { rawCell>>8, rawCell,            // bytes 0-1
                         0,0,                            // bytes 2-3  (temps if wanted)
                         soc,                            // byte 4
                         flags };                       // byte 5
    canSend(ID_ACM_CELL_INFO, d102, 6);
}

static void handleCommand(const twai_message_t &m)
{
    switch (m.identifier) {

    case ID_CMD_LC_SWITCH: {
        uint8_t idx   = m.data[0] & 0x07;          // 0 … 7  (LC1…8)
        bool    state = (m.data[0] & 0x08) != 0;
        if (idx < 8) {
            lowCurrentStates[idx] = state;
            digitalWrite(getLowCurrentPin(idx + 1), state ? HIGH : LOW);
        }
        break;
    }

    case ID_CMD_LC_BRIGHTNESS: {
        uint8_t idx = m.data[0] & 0x07;
        uint8_t bri = m.data[1];
        if (idx < 8) {
            lowCurrentBrightness[idx] = bri;
            if (lowCurrentStates[idx])
                analogWrite(getLowCurrentPin(idx + 1), bri);
        }
        break;
    }

    case ID_CMD_MC_SWITCH: {
        uint8_t idx   = m.data[0] & 0x03;          // 0 or 1
        bool    state = (m.data[0] & 0x04) != 0;
        if (idx < 2) {
            mediumCurrentStates[idx] = state;
            digitalWrite(getMediumCurrentPin(idx + 1), state ? HIGH : LOW);
        }
        break;
    }

    case ID_CMD_INV_SWITCH: {
        bool state = (m.data[0] & 0x04) != 0;
        // same pulse trick you already use:
        mcp.digitalWrite(INV_CTRL, HIGH);
        delay(250);
        mcp.digitalWrite(INV_CTRL, LOW);
        break;
    }
    }
}

void canTick()
{
    /* 1) TX side — periodic scheduling */
    uint32_t now = millis();

    if (now - tLastHb >= 1000) {          // 1 Hz
        tLastHb = now;
        sendHeartbeat();
        sendTelemetry1Hz();
    }
    if (now - tLast2Hz >= 500) {          // 2 Hz
        tLast2Hz = now;
        sendTelemetry2Hz();
    }
    if (now - tLast10Hz >= 100) {         // 10 Hz
        tLast10Hz = now;
        sendTelemetry10Hz();
    }

    /* 2) RX side — empty the queue */
    twai_message_t rx;
    while (twai_receive(&rx, 0) == ESP_OK) {
        handleCommand(rx);
    }
}


bool initCAN()
{
    twai_general_config_t g_config =
        TWAI_GENERAL_CONFIG_DEFAULT((gpio_num_t)CAN_TX,
                                    (gpio_num_t)CAN_RX,
                                    TWAI_MODE_NORMAL);     // classical CAN

    twai_timing_config_t  t_config = TWAI_TIMING_CONFIG_250KBITS();
    twai_filter_config_t  f_config = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    if (twai_driver_install(&g_config, &t_config, &f_config) != ESP_OK) {
        Serial.println("[CAN] driver install failed");
        return false;
    }
    if (twai_start() != ESP_OK) {
        Serial.println("[CAN] start failed");
        return false;
    }
    // enable basic alerts so we can poll errors if desired
    twai_reconfigure_alerts(TWAI_ALERT_ERR_PASS | TWAI_ALERT_BUS_ERROR, nullptr);
    Serial.println("[CAN] up @ 250 kbit s-1");
    return true;
}

void startBLEAdvertising() {
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    BLEAdvertisementData advertisementData;
    BLEAdvertisementData scanResponseData;

    advertisementData.setCompleteServices(BLEUUID(SERVICE_UUID));
    scanResponseData.setName(bleDeviceName.c_str());

    pAdvertising->stop();
    pAdvertising->setAdvertisementData(advertisementData);
    pAdvertising->setScanResponseData(scanResponseData);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMaxPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.print("BLE advertising as: ");
    Serial.println(bleDeviceName);
}


// ----------------------------------------------------------------------
// Setup
// ----------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    loadConfiguration();

    Serial1.begin(19200, SERIAL_8N1, 9, 8);
    Serial.println("Serial1 (Victron) initialized at 19200 baud");

    // BMS Serial2 at 115200
    SerialBMS.begin(115200, SERIAL_8N1, U2_RX, U2_TX);
    Serial.println("Serial2 (JK-BMS) initialized at 115200 baud");

    // Initialize MCP23S17 (SPI)
    if (!mcp.begin_SPI(MCP_ChipSelect)) {
        Serial.println("Failed to initialize MCP23S17");
        while (1);
    }

    // Setup MCP
    mcp.pinMode(Q1_SEn, OUTPUT);
    mcp.pinMode(Q1_SEL0, OUTPUT);
    mcp.pinMode(Q1_SEL1, OUTPUT);
    mcp.pinMode(Q1_RST, OUTPUT);
    mcp.pinMode(Q2_SEn, OUTPUT);
    mcp.pinMode(Q2_SEL0, OUTPUT);
    mcp.pinMode(Q2_SEL1, OUTPUT);
    mcp.pinMode(Q2_RST, OUTPUT);
    mcp.pinMode(D_SEn, OUTPUT);
    mcp.pinMode(D_SEL, OUTPUT);
    mcp.pinMode(D_RST, OUTPUT);
    mcp.pinMode(INV_CTRL, OUTPUT);

    pinMode(LC1, OUTPUT);
    pinMode(LC2, OUTPUT);
    pinMode(LC3, OUTPUT);
    pinMode(LC4, OUTPUT);
    pinMode(LC5, OUTPUT);
    pinMode(LC6, OUTPUT);
    pinMode(LC7, OUTPUT);
    pinMode(LC8, OUTPUT);
    pinMode(MC1, OUTPUT);
    pinMode(MC2, OUTPUT);

    pinMode(V_SENSE, INPUT); 
    mcp.digitalWrite(Q1_SEn, HIGH);
    mcp.digitalWrite(Q2_SEn, HIGH);
    mcp.digitalWrite(INV_CTRL, LOW); // ensure default LOW
    pinMode(INV_STATE, INPUT);


    // can init
    initCAN();

    // BLE init
    bleDeviceName = "ESP32_ACM_" + String(ACM_SERIAL_NUMBER);
    BLEDevice::init(bleDeviceName.c_str());
    BLEServer *pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyCallbacks());
    BLEService *pService = pServer->createService(SERVICE_UUID);

    pCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_READ |
                        BLECharacteristic::PROPERTY_WRITE |
                        BLECharacteristic::PROPERTY_NOTIFY |
                        BLECharacteristic::PROPERTY_WRITE_NR
                      );

    pCharacteristic->setCallbacks(new CharacteristicCallbacks());
    pCharacteristic->addDescriptor(new BLE2902());
    String initialValue = "SN:" + String(ACM_SERIAL_NUMBER);
    pCharacteristic->setValue(initialValue.c_str());
    pService->start();

    BLEDevice::setMTU(185);
    reconfigureSerial1Mode();
    startBLEAdvertising();

    // Initialize voltage/current buffers
    for (int i = 0; i < voltageBufferSize; i++) {
        voltageBuffer[i] = 0.0;
    }
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < currentBufferSize; j++) {
            lowCurrentBuffers[i][j] = 0.0;
        }
    }
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < currentBufferSize; j++) {
            mediumCurrentBuffers[i][j] = 0.0;
        }
    }

    // Create a task to send sensor data frequently
    xTaskCreate(
        [](void*) {
            while (true) {
                sendSensorData();
                vTaskDelay(500 / portTICK_PERIOD_MS); // Send data every 500 ms
            }
        },
        "SendSensorData",
        4096,
        nullptr,
        1,
        nullptr
    );
}

// ----------------------------------------------------------------------
// Main Loop
// ----------------------------------------------------------------------
void loop() {
    // 1) Poll the JK-BMS ~every 1s (only if JK protocol selected and feature enabled)
    static unsigned long lastBmsPoll = 0;
    if (featureBmsEnabled && bmsProto == BP_JK) {
    if (millis() - lastBmsPoll >= 1000) {
        lastBmsPoll = millis();
        pollBms();
    }
    } else {
    // Not using JK; ensure its flag doesn’t linger
    // (BMV will set bmsConnected via VE.Direct)
    }
    getSensor();

    // If we haven't received new BMS data in >3s, mark bmsConnected false
    if (featureBmsEnabled && bmsProto == BP_JK) {
    if (bmsConnected && (millis() - lastBmsDataMillis > 3000)) {
        bmsConnected = false;
    }
    }


    // 2) Check battery voltage logic
    checkBatteryVoltage(); 
    manageErrorState();

    canTick();
    delay(2);
    
    // 3) Process VE.Direct (Serial1) data for either SOLAR or BMV depending on serial1Mode
    while (Serial1.available()) {
    char incomingByte = Serial1.read();
    checksumSum += (unsigned char)incomingByte;

    if (blockIndex < MAX_BLOCK_SIZE - 1) {
        blockBuffer[blockIndex++] = incomingByte;
    } else {
        // overflow -> reset
        blockIndex = 0;
        checksumSum = 0;
        currentLine = "";
        break;
    }

    if (incomingByte == '\n') {
        if (currentLine.endsWith("\r")) {
        currentLine.remove(currentLine.length() - 1);
        }
        if (currentLine.startsWith("Checksum\t")) {
        if ((checksumSum % 256) == 0) {
            blockBuffer[blockIndex] = '\0';
            if (serial1Mode == SERIAL1_SOLAR) {
            parseVEDirectBlockSolar(blockBuffer);
            } else if (serial1Mode == SERIAL1_BMV) {
            parseVEDirectBlockBMV(blockBuffer);
            }
        }
        // Reset block regardless
        blockIndex = 0;
        checksumSum = 0;
        }
        currentLine = "";
    } else {
        currentLine += incomingByte;
    }
    }

    // Watchdog: mark each source separately
    if (serial1Mode == SERIAL1_SOLAR) {
    if (solarVedirectActive && (millis() - lastSerialDataMillis > WATCHDOG_TIMEOUT)) {
        solarVedirectActive = false;
    }
    } else if (serial1Mode == SERIAL1_BMV) {
    if (bmvVedirectActive && (millis() - lastSerialDataMillis > WATCHDOG_TIMEOUT)) {
        bmvVedirectActive = false;
        bmsConnected = false; // BMV stopped sending
    }
    }



    
}

// ----------------------------------------------------------------------
// Adjusted checkBatteryVoltage: uses BMS if connected, else fallback
// ----------------------------------------------------------------------
void checkBatteryVoltage() {
    unsigned long currentMillis = millis();
    if (currentMillis - lastVoltageReadMillis >= 100) {
        lastVoltageReadMillis = currentMillis;

        // If we have BMS data, use it. Otherwise, read from the voltage divider
        if (bmsConnected && bmsVoltage > 0.0f) {
          batteryVoltage = bmsVoltage;
        } else {
          batteryVoltage = readRealVoltage();
        }
    }

    if (!autoCutoffEnabled && outputsDisabled) {
        outputsDisabled = false;
    }

    if (autoCutoffEnabled && batteryVoltage < critVoltage) {
        handleAutoShutdownWarning();
    } else if (autoCutoffEnabled && batteryVoltage < cutOutVoltage && !outputsDisabled) {
        disableOutputs();
    } else if (autoCutoffEnabled && batteryVoltage < cutOutVoltage + 0.2) {
        flashLED('Y', 3, 500);
    } else if (batteryVoltage >= cutInVoltage && outputsDisabled) {
        outputsDisabled = false;
        setLEDColor('G');
    }
    // Now enforce Always-On & Priority channels here:
    updateChannels();
}

// ----------------------------------------------------------------------
// Update sendSensorData to include BMS connectivity & values
// ----------------------------------------------------------------------
String floatToHex(float value, int scale);
String stateToHex(bool state);

void sendSensorData() {
    // If bmsConnected => use BMS current for BLE or keep your existing logic?
    // We'll just share BMS current in a new field. Or you can do whatever you want.

    // In your original code, you assemble voltageCurrentSection with:
    //   batteryVoltage (from the global), totalCurrent, solarVoltage, solarCurrent, ...
    // We'll add the BMS connect flag similarly to how we do "connectionFlag" for victron.
    float inverterVoltage = readInverterVoltage();
    // Voltage & Current:
    String batteryVoltageHex = floatToHex(batteryVoltage, 100);
    String cellAvgHex = floatToHex(avgCellVoltage, 100);
    // bmsCurrent is encoded with a +512 A offset so negative values can cross BLE as hex.
    String currentUsageBMSHex = floatToHex(bmsCurrent + 512, 10);
    // Solar from your code:
    String solarVoltageHex = floatToHex(VPV, 100);
    String solarCurrentHex = floatToHex(I, 100);
    String solarPowerHex = floatToHex(PPV, 100);
    String solarStateHex = floatToHex(CS, 1);
    Serial.println(bmsCurrent);

    String batTemp1Hex = floatToHex(batTemp1, 100);

    String batSocHex = floatToHex(bmsSoc, 100);
    // Serial.println(sensor1);
    String sensor1Hex = floatToHex(sensor1, 100);

    // Convert to a hex string (scaled by 100, for example)
    String inverterHex = floatToHex(inverterVoltage, 100);

    // Victron connection flag:
    String connectionFlag = (solarVedirectActive && serial1Mode == SERIAL1_SOLAR) ? "1" : "0";
    
    String bmsFlag        = bmsConnected ? "1" : "0";  // true if JK good OR BMV good


    totalCurrent = 0.0f;

    // Low current channels
    String loadChannelsSection = "L:";
    for (int i = 0; i < 8; i++) {
        String stateHex = stateToHex(lowCurrentStates[i]);
        String brightnessHex = String(lowCurrentBrightness[i], HEX);
        float current = (i < 4) ? readQuadCurrent(i, Q1_SEL0, Q1_CS) 
                                : readQuadCurrent(i - 4, Q2_SEL0, Q2_CS);
        String currentHex = floatToHex(current, 1000);
        loadChannelsSection += stateHex + brightnessHex + currentHex + ((i < 7) ? "," : ";");
    }

    // Medium current channels
    String mediumChannelsSection = "M:";
    for (int i = 0; i < 2; i++) {
        String stateHex = stateToHex(mediumCurrentStates[i]);
        float current = readDualCurrent(i);
        String currentHex = floatToHex(current, 1000);
        mediumChannelsSection += stateHex + currentHex + ((i < 1) ? "," : ";");
    }

    float outputCurrentForTelemetry = bmsConnected ? 0.0f : totalCurrent;
    String currentUsageHex = floatToHex(outputCurrentForTelemetry, 100);

    String voltageCurrentSection = "V:" + batteryVoltageHex + "," + currentUsageBMSHex + "," + currentUsageHex + "," 
                                     + solarVoltageHex + "," + solarCurrentHex + "," 
                                     + solarPowerHex + "," + solarStateHex + "," + cellAvgHex  + "," + batTemp1Hex + "," + batSocHex + "," + sensor1Hex + "," 
                                     + connectionFlag + "," + bmsFlag + ";" ;

    
    // Add an inverter section to the data packet, e.g. "I:0FA6;"
    // (whatever formatting you prefer)
    String inverterSection = "I:" + inverterHex + ";";


    // After building voltageCurrentSection / L / M / I...
    String extrasSection = "";
    if (serial1Mode == SERIAL1_BMV && bmvVedirectActive) {
    // encode as plain decimal (or hex—your choice; below keeps it simple)
    extrasSection = "B:" + String(CE_mAh) + "," + String(TTG_min) + ";";
    }

    String serialSection = "SN:" + String(ACM_SERIAL_NUMBER) + ";";
    String dataPacket = voltageCurrentSection + loadChannelsSection + mediumChannelsSection + inverterSection + extrasSection + serialSection;
    pCharacteristic->setValue(dataPacket.c_str());
    pCharacteristic->notify();


    Serial.println("Data sent: " + dataPacket);
}

// Helper for hex conversions
String floatToHex(float value, int scale) {
    return String((int)(value * scale), HEX);
}
String stateToHex(bool state) {
    return state ? "1" : "0";
}

// ----------------------------------------------------------------------
// The rest are your original utility functions
// ----------------------------------------------------------------------
void disableOutputs() {
    for (int i = 1; i <= 8; i++) {
        digitalWrite(getLowCurrentPin(i), LOW);
    }
    for (int i = 1; i <= 2; i++) {
        digitalWrite(getMediumCurrentPin(i), LOW);
    }
    outputsDisabled = true;
    flashLED('R', 3, 300);
}

void handleAutoShutdownWarning() {
    pulseLED('R', 1000);
}

void setLEDColor(char color) {
    // Placeholder for your neopixelWrite or LED code
    // e.g. neopixelWrite(RGB_BUILTIN, r, g, b)
}

void flashLED(char color, int times, int delayTime) {
    for (int i = 0; i < times; i++) {
        setLEDColor(color);
        delay(delayTime);
        setLEDColor('O');
        delay(delayTime);
    }
}

void pulseLED(char color, int pulseDuration) {
    // Basic example
    for (int i = 0; i < RGB_BRIGHTNESS; i++) {
        // e.g. neopixelWrite(RGB_BUILTIN, i,0,0) if color=='R'
        delay(pulseDuration / RGB_BRIGHTNESS);
    }
    for (int i = RGB_BRIGHTNESS; i >= 0; i--) {
        // ...
        delay(pulseDuration / RGB_BRIGHTNESS);
    }
}

void handleConnectionIndicator() {
    flashLED('G', 1, 250);
}

void handleCommandReceivedIndicator() {
    flashLED('B', 1, 250);
}

void handleErrorIndicator(int code) {
    errorCode = code;
    errorPresent = true;
    manageErrorState();
}

void manageErrorState() {
    if (errorPresent) {
        if (errorCode == 1) {
            flashLED('R', 2, 300);
        } else if (errorCode == 2) {
            flashLED('M', 3, 300);
        }
    }
}

// Reads the actual sense pin for fallback
float readRealVoltage() {
    int analogValue = analogRead(V_SENSE);
    float measuredVoltage = (analogValue * 3.3 / 4095.0) * voltageDividerRatio;
    return measuredVoltage * voltageCalibrationFactor;
}

int getLowCurrentPin(int index) {
    switch (index) {
        case 1: return LC1;
        case 2: return LC2;
        case 3: return LC3;
        case 4: return LC4;
        case 5: return LC5;
        case 6: return LC6;
        case 7: return LC7;
        case 8: return LC8;
        default: return -1;
    }
}

int getMediumCurrentPin(int index) {
    switch (index) {
        case 1: return MC1;
        case 2: return MC2;
        default: return -1;
    }
}

float readQuadCurrent(int channel, int selectPin, int sensePin) {
    mcp.digitalWrite(selectPin, channel & 0x01);
    mcp.digitalWrite(selectPin + 1, (channel >> 1) & 0x01);
    delay(10);
    int adcValue = analogRead(sensePin);
    float voltage = adcValue * (3.3 / 4095.0) * 1000;
    float current = (voltage / 1000.0) * 5050;
    if (selectPin == Q2_SEL0) channel += 4;

    lowCurrentBuffers[channel][lowCurrentIndex[channel]] = current;
    lowCurrentIndex[channel] = (lowCurrentIndex[channel] + 1) % currentBufferSize;

    float sum = 0.0;
    for (int i = 0; i < currentBufferSize; i++) {
        sum += lowCurrentBuffers[channel][i];
    }
    float avCurrent = sum / currentBufferSize;
    totalCurrent += avCurrent;
    return avCurrent;
}

float readDualCurrent(int channel) {
    mcp.digitalWrite(D_SEL, channel & 0x01);
    delay(10);
    int adcValue = analogRead(D_CS);
    float voltage = adcValue * (3.3 / 4095.0) * 1000;
    float current = (voltage / 1000.0) * 9150;

    mediumCurrentBuffers[channel][mediumCurrentIndex[channel]] = current;
    mediumCurrentIndex[channel] = (mediumCurrentIndex[channel] + 1) % currentBufferSize;

    float sum = 0.0;
    for (int i = 0; i < currentBufferSize; i++) {
        sum += mediumCurrentBuffers[channel][i];
    }
    float avCurrent = sum / currentBufferSize;
    totalCurrent += avCurrent;
    return avCurrent;
}

void applyConfiguration(const std::string &config) {
    size_t pos = 0;
    size_t next_pos = 0;

    Serial.print("Config received: ");
    Serial.println(config.c_str());

    pos = config.find("CO");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string cutOutStr = config.substr(pos, next_pos - pos);
        cutOutVoltage = atof(cutOutStr.c_str());
        Serial.print("Cut Out Voltage: ");
        Serial.println(cutOutVoltage);
    }

    pos = config.find("CI");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string cutInStr = config.substr(pos, next_pos - pos);
        cutInVoltage = atof(cutInStr.c_str());
        Serial.print("Cut In Voltage: ");
        Serial.println(cutInVoltage);
    }

    pos = config.find("AC");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        autoCutoffEnabled = config.substr(pos, next_pos - pos) == "1";
        Serial.print("Auto Cutoff Enabled: ");
        Serial.println(autoCutoffEnabled);
    }

    pos = config.find("AO");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string aoString = config.substr(pos, next_pos - pos);
        if (aoString.length() >= 10) {
            for (int i = 0; i < 10; ++i) {
                alwaysOnChannels[i] = aoString[i] == '1';
            }
        } else {
            Serial.println("Invalid Always-On channel mask; keeping previous values.");
        }
    }
    
    pos = config.find("PR");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string prString = config.substr(pos, next_pos - pos);
        if (prString.length() >= 10) {
            for (int i = 0; i < 10; ++i) {
                priorityChannels[i] = prString[i] == '1';
            }
        } else {
            Serial.println("Invalid Priority channel mask; keeping previous values.");
        }
        Serial.print("Priority Channels: ");
        for (int i = 0; i < 10; ++i) {
            Serial.print(priorityChannels[i]);
        }
        Serial.println();
    }

        // Feature BMS: FB0/FB1
    pos = config.find("FB");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string fbStr = config.substr(pos, (next_pos == std::string::npos ? config.size() : next_pos) - pos);
        featureBmsEnabled = (fbStr == "1");
        Serial.printf("FB (featureBmsEnabled): %d\n", featureBmsEnabled);
    }

    // Battery Protocol: BP=NONE|JK|BMV
    pos = config.find("BP");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string bpStr = config.substr(pos, (next_pos == std::string::npos ? config.size() : next_pos) - pos);
        if      (bpStr == "JK")   bmsProto = BP_JK;
        else if (bpStr == "BMV")  bmsProto = BP_BMV;
        else                      bmsProto = BP_NONE;
        Serial.printf("BP: %s\n", bpStr.c_str());
    }

    // Feature Solar: FS0/FS1  (ignored if BMV is selected)
    pos = config.find("FS");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string fsStr = config.substr(pos, (next_pos == std::string::npos ? config.size() : next_pos) - pos);
        featureSolarEnabled = (fsStr == "1");
        Serial.printf("FS (featureSolarEnabled): %d\n", featureSolarEnabled);
    }

    // Solar Protocol: SP=NONE|VIC
    pos = config.find("SP");
    if (pos != std::string::npos) {
        pos += 2;
        next_pos = config.find(" ", pos);
        std::string spStr = config.substr(pos, (next_pos == std::string::npos ? config.size() : next_pos) - pos);
        if      (spStr == "VIC") solarProto = SP_VIC;
        else                     solarProto = SP_NONE;
        Serial.printf("SP: %s\n", spStr.c_str());
    }

    // Apply cross-coupling rule (BMV uses VE.Direct, so Solar must be off)
    reconfigureSerial1Mode();
    saveConfiguration();

}
