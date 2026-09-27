@import XCTest;

#import "ArcLaunchUpdateChecker.h"

@interface ArcLaunchUpdateCheckerTests : XCTestCase
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation ArcLaunchUpdateCheckerTests

- (void)setUp {
    [super setUp];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"ArcLaunchUpdateTests.%@", [[NSUUID UUID] UUIDString]]];
}

// 模拟 CI 生成的滚动 Release：标题和说明带版本号，附带校验文件与构建日志。
- (NSDictionary *)releaseJSONWithVersion:(NSString *)version {
    NSString *assetName = [NSString stringWithFormat:@"ArcLaunch_%@.tipa", version];
    NSString *downloadURL = [@"https://github.com/KleinerSource/ArcLaunch/releases/download/latest/" stringByAppendingString:[assetName stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];
    NSString *body = [NSString stringWithFormat:@"版本: %@\r\n\r\n本次构建包含以下更新：\r\n\r\nfeat(settings): 新增自动检查更新\r\n - 启动时检查 GitHub\r\n\r\ncommit: [abc1234](https://github.com/KleinerSource/ArcLaunch/commit/abc1234)\r\nrun: [12](https://github.com/KleinerSource/ArcLaunch/actions/runs/1)", version];
    return @{
        @"tag_name": @"latest",
        @"name": [NSString stringWithFormat:@"ArcLaunch %@", version],
        @"draft": @NO,
        @"html_url": @"https://github.com/KleinerSource/ArcLaunch/releases/tag/latest",
        @"body": body,
        @"assets": @[
            @{@"name": [assetName stringByAppendingString:@".sha256"], @"browser_download_url": [downloadURL stringByAppendingString:@".sha256"]},
            @{@"name": @"xcodebuild.log", @"browser_download_url": @"https://github.com/KleinerSource/ArcLaunch/releases/download/latest/xcodebuild.log"},
            @{@"name": assetName, @"browser_download_url": downloadURL},
        ],
    };
}

- (ArcLaunchUpdateChecker *)checkerWithCurrentVersion:(NSString *)currentVersion statusCode:(NSInteger)statusCode JSONObject:(id)JSONObject {
    NSData *data = JSONObject ? [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:nil] : nil;
    return [[ArcLaunchUpdateChecker alloc] initWithReleaseURL:[NSURL URLWithString:@"https://api.github.com/repos/KleinerSource/ArcLaunch/releases/tags/latest"] currentVersion:[ArcLaunchAppVersion versionFromString:currentVersion] userDefaults:self.defaults fetcher:^(NSURLRequest * _Nonnull request, ArcLaunchUpdateFetchCompletion _Nonnull completion) {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:nil];
        completion(data, response, nil);
    }];
}

- (void)testVersionParsingAndOrdering {
    XCTAssertEqualObjects([ArcLaunchAppVersion versionFromString:@"ArcLaunch_1.2.3+45.tipa"].stringValue, @"1.2.3+45");
    XCTAssertEqualObjects([ArcLaunchAppVersion versionFromString:@"版本: v0.10.0"].stringValue, @"0.10.0+0");
    XCTAssertEqualObjects([ArcLaunchAppVersion versionFromString:@"1.2.3+45"].displayString, @"1.2.3 (45)");
    XCTAssertNil([ArcLaunchAppVersion versionFromString:@"ArcLaunch 测试构建"]);
    XCTAssertEqualObjects([ArcLaunchAppVersion versionWithShortVersion:@"1.0" buildNumber:@"7"].stringValue, @"1.0.0+7");
    XCTAssertNil([ArcLaunchAppVersion versionWithShortVersion:@"1.0-beta" buildNumber:@"7"]);

    ArcLaunchAppVersion *version = [ArcLaunchAppVersion versionFromString:@"1.2.3+45"];
    XCTAssertEqual([version compare:[ArcLaunchAppVersion versionFromString:@"1.2.3+46"]], NSOrderedAscending);
    XCTAssertEqual([version compare:[ArcLaunchAppVersion versionFromString:@"1.10.0+1"]], NSOrderedAscending);
    XCTAssertEqual([version compare:[ArcLaunchAppVersion versionFromString:@"1.2.2+99"]], NSOrderedDescending);
    XCTAssertEqual([version compare:[ArcLaunchAppVersion versionFromString:@"1.2.3+45"]], NSOrderedSame);
}

- (void)testReleaseParsingPicksTIPAAndStripsBuildMetadata {
    ArcLaunchRelease *release = [ArcLaunchRelease releaseFromJSONObject:[self releaseJSONWithVersion:@"1.3.0+52"]];
    XCTAssertNotNil(release);
    XCTAssertEqualObjects(release.version.stringValue, @"1.3.0+52");
    XCTAssertEqualObjects(release.assetName, @"ArcLaunch_1.3.0+52.tipa");
    XCTAssertEqualObjects(release.downloadURL.absoluteString, @"https://github.com/KleinerSource/ArcLaunch/releases/download/latest/ArcLaunch_1.3.0%2B52.tipa");
    XCTAssertEqualObjects(release.pageURL.absoluteString, @"https://github.com/KleinerSource/ArcLaunch/releases/tag/latest");
    XCTAssertEqualObjects(release.notes, @"feat(settings): 新增自动检查更新\n - 启动时检查 GitHub");
}

- (void)testVersionFallsBackToAssetName {
    NSDictionary *JSON = @{
        @"tag_name": @"latest",
        @"name": @"ArcLaunch 测试构建",
        @"body": @"自动测试构建",
        @"assets": @[@{@"name": @"ArcLaunch_2.0.1+9.ipa", @"browser_download_url": @"https://example.com/ArcLaunch_2.0.1+9.ipa"}],
    };
    ArcLaunchRelease *release = [ArcLaunchRelease releaseFromJSONObject:JSON];
    XCTAssertEqualObjects(release.version.stringValue, @"2.0.1+9");
    XCTAssertEqualObjects(release.notes, @"自动测试构建");
}

- (void)testUnusableReleasesAreRejected {
    NSMutableDictionary *draft = [[self releaseJSONWithVersion:@"1.3.0+52"] mutableCopy];
    draft[@"draft"] = @YES;
    XCTAssertNil([ArcLaunchRelease releaseFromJSONObject:draft]);

    NSMutableDictionary *withoutPackage = [[self releaseJSONWithVersion:@"1.3.0+52"] mutableCopy];
    withoutPackage[@"assets"] = @[@{@"name": @"xcodebuild.log", @"browser_download_url": @"https://example.com/xcodebuild.log"}];
    XCTAssertNil([ArcLaunchRelease releaseFromJSONObject:withoutPackage]);

    NSMutableDictionary *insecure = [[self releaseJSONWithVersion:@"1.3.0+52"] mutableCopy];
    insecure[@"assets"] = @[@{@"name": @"ArcLaunch.tipa", @"browser_download_url": @"http://example.com/ArcLaunch.tipa"}];
    XCTAssertNil([ArcLaunchRelease releaseFromJSONObject:insecure]);

    NSMutableDictionary *unversioned = [[self releaseJSONWithVersion:@"1.3.0+52"] mutableCopy];
    unversioned[@"name"] = @"ArcLaunch 测试构建";
    unversioned[@"body"] = @"自动测试构建";
    unversioned[@"assets"] = @[@{@"name": @"ArcLaunch.tipa", @"browser_download_url": @"https://example.com/ArcLaunch.tipa"}];
    XCTAssertNil([ArcLaunchRelease releaseFromJSONObject:unversioned]);

    XCTAssertNil([ArcLaunchRelease releaseFromJSONObject:@[]]);
}

- (void)testInstallURLHandsExactDownloadURLToTrollStore {
    ArcLaunchRelease *release = [ArcLaunchRelease releaseFromJSONObject:[self releaseJSONWithVersion:@"1.3.0+52"]];
    NSURL *installURL = [ArcLaunchUpdateChecker installURLForRelease:release];
    XCTAssertEqualObjects(installURL.scheme, @"apple-magnifier");
    XCTAssertEqualObjects(installURL.host, @"install");
    // TrollStore 用 NSURLComponents 读取 url 参数，解码后必须与原始下载地址一致。
    NSURLComponents *components = [NSURLComponents componentsWithURL:installURL resolvingAgainstBaseURL:NO];
    XCTAssertEqual(components.queryItems.count, 1);
    XCTAssertEqualObjects(components.queryItems.firstObject.name, @"url");
    XCTAssertEqualObjects(components.queryItems.firstObject.value, release.downloadURL.absoluteString);
}

- (void)testCheckFindsUpdateAndRemembersIgnoredVersion {
    ArcLaunchUpdateChecker *checker = [self checkerWithCurrentVersion:@"1.2.9+51" statusCode:200 JSONObject:[self releaseJSONWithVersion:@"1.3.0+52"]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"update check"];
    [checker checkForUpdatesWithCompletion:^(ArcLaunchRelease * _Nullable release, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertTrue([checker isUpdateRelease:release]);
        XCTAssertFalse([checker isReleaseIgnored:release]);
        [checker ignoreRelease:release];
        XCTAssertTrue([checker isReleaseIgnored:release]);
        [expectation fulfill];
    }];
    XCTAssertTrue(checker.isChecking);
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertFalse(checker.isChecking);
    XCTAssertNotNil(checker.lastCheckDate);
    XCTAssertNil(checker.lastError);
    XCTAssertEqualObjects(checker.latestRelease.version.stringValue, @"1.3.0+52");

    // 忽略只针对那一个版本，更新的构建仍会提示。
    ArcLaunchRelease *newerRelease = [ArcLaunchRelease releaseFromJSONObject:[self releaseJSONWithVersion:@"1.3.1+53"]];
    XCTAssertFalse([checker isReleaseIgnored:newerRelease]);
}

- (void)testSameVersionIsNotAnUpdate {
    ArcLaunchUpdateChecker *checker = [self checkerWithCurrentVersion:@"1.3.0+52" statusCode:200 JSONObject:[self releaseJSONWithVersion:@"1.3.0+52"]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"up to date"];
    [checker checkForUpdatesWithCompletion:^(ArcLaunchRelease * _Nullable release, NSError * _Nullable error) {
        XCTAssertNotNil(release);
        XCTAssertFalse([checker isUpdateRelease:release]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHTTPFailureIsReported {
    ArcLaunchUpdateChecker *checker = [self checkerWithCurrentVersion:@"1.0.0+1" statusCode:404 JSONObject:@{@"message": @"Not Found"}];
    XCTestExpectation *expectation = [self expectationWithDescription:@"failed check"];
    [checker checkForUpdatesWithCompletion:^(ArcLaunchRelease * _Nullable release, NSError * _Nullable error) {
        XCTAssertNil(release);
        XCTAssertEqualObjects(error.domain, ArcLaunchUpdateErrorDomain);
        XCTAssertEqual(error.code, ArcLaunchUpdateErrorHTTPStatus);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertNil(checker.latestRelease);
    XCTAssertNotNil(checker.lastError);
    XCTAssertNil(checker.lastCheckDate);
}

- (void)testConcurrentChecksShareOneRequest {
    __block NSUInteger requestCount = 0;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self releaseJSONWithVersion:@"1.3.0+52"] options:0 error:nil];
    ArcLaunchUpdateChecker *checker = [[ArcLaunchUpdateChecker alloc] initWithReleaseURL:[NSURL URLWithString:@"https://example.com/release"] currentVersion:[ArcLaunchAppVersion versionFromString:@"1.0.0+1"] userDefaults:self.defaults fetcher:^(NSURLRequest * _Nonnull request, ArcLaunchUpdateFetchCompletion _Nonnull completion) {
        requestCount++;
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, response, nil);
        });
    }];
    XCTestExpectation *first = [self expectationWithDescription:@"first caller"];
    XCTestExpectation *second = [self expectationWithDescription:@"second caller"];
    [checker checkForUpdatesWithCompletion:^(ArcLaunchRelease * _Nullable release, NSError * _Nullable error) {
        XCTAssertNotNil(release);
        [first fulfill];
    }];
    [checker checkForUpdatesWithCompletion:^(ArcLaunchRelease * _Nullable release, NSError * _Nullable error) {
        XCTAssertNotNil(release);
        [second fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(requestCount, 1);
}

- (void)testAutomaticCheckDefaultsToEnabledAndPersists {
    ArcLaunchUpdateChecker *checker = [self checkerWithCurrentVersion:@"1.0.0+1" statusCode:200 JSONObject:nil];
    XCTAssertTrue(checker.automaticCheckEnabled);
    checker.automaticCheckEnabled = NO;
    ArcLaunchUpdateChecker *reloadedChecker = [self checkerWithCurrentVersion:@"1.0.0+1" statusCode:200 JSONObject:nil];
    XCTAssertFalse(reloadedChecker.automaticCheckEnabled);
}

@end
