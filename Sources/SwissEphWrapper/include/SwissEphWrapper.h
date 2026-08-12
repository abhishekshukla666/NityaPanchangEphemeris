//
//  SwissEphWrapper.h
//  NityaPanchangam
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SwissEphWrapper : NSObject

/// Purnimanta tithi number (1–30): Krishna 1–15 (1=Pratipada … 15=Amavasya),
/// then Shukla 16–30 (16=Pratipada … 30=Purnima).
- (int)calculateTithiNumberForJulianDay:(double)jd;
- (NSDictionary *)calculateTithiForDate:(NSDate *)date
                               latitude:(double)latitude
                              longitude:(double)longitude;

- (NSDictionary *)calculateSunriseSunsetForDate:(NSDate *)date
                                       latitude:(double)latitude
                                      longitude:(double)longitude;

/// Solar month (Saura Mana): Sun's current sidereal rashi → 1–12 (Chaitra=1…Phalguna=12).
- (int)calculateLunarMonthForJulianDay:(double)jd;

/// Purnimanta month: Sun's rashi at the NEXT upcoming Purnima → 1–12.
/// The upcoming Purnima always closes the current Purnimanta month, regardless of paksha.
- (int)calculatePurnimantaMonthForJulianDay:(double)jd;

/// Amanta month: Sun's rashi at the Purnima within the current Amanta month → 1–12.
/// For Shukla Paksha this is the upcoming Purnima; for Krishna Paksha it is the last one.
//- (int)calculateAmantaMonthForJulianDay:(double)jd;

/// Amanta Adhik Maas: no Sankranti between the two Amavasyas bracketing the current date.
/// Use this for Amanta and Solar calendar display.
- (BOOL)calculateIsAdhikMaasForJulianDay:(double)jd;

/// Purnimanta Adhik Maas: checks whether the upcoming Purnima (which closes the current
/// Purnimanta month) falls within an Amanta Adhik window.
/// This is the correct criterion for Purnimanta display: the Adhik period ends at the
/// Purnima (not the Amavasya), giving a full-length regular month immediately after.
- (BOOL)calculateIsPurnimantaAdhikMaasForJulianDay:(double)jd;

- (double)getJulianDayUTCFromDate:(NSDate *)date;

- (int)calculateYogaForJulianDay:(double)jd;
- (int)calculateNakshatraForJulianDay:(double)jd;
- (double)calculateNakshatraEndTimeForJulianDay:(double)startJD;

- (NSDictionary *)calculateMuhuratsWithSunrise:(double)sunriseJD sunset:(double)sunsetJD weekday:(int)weekday;
- (double)calculateYogaEndTimeForJulianDay:(double)startJD;
- (int)calculateMoonRashiForJulianDay:(double)jd;

/// Returns an array of 9 NSDictionary objects (one per Navagraha).
/// Each dict has: planetIndex (0–8), longitude (0–360), rashiNumber (1–12), degreesInSign (0–30).
- (NSArray<NSDictionary *> *)calculatePlanetPositionsForJulianDay:(double)jd;

/// Returns the sidereal Ascendant (Lagna) longitude in degrees (0–360) using Lahiri ayanamsha.
- (double)calculateAscendantAtJD:(double)jd latitude:(double)lat longitude:(double)lon;

@end

NS_ASSUME_NONNULL_END
