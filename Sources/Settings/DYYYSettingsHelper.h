#import <Foundation/Foundation.h>
#import "AwemeHeaders.h"

@interface DYYYSettingsHelper : NSObject

/** 获取用户默认设置（布尔值） */
+ (BOOL)getUserDefaults:(NSString *)key;

/** 设置用户默认值 */
+ (void)setUserDefaults:(id)object forKey:(NSString *)key;

/** 显示自定义关于弹窗 */
+ (void)showAboutDialog:(NSString *)title message:(NSString *)message onConfirm:(void (^)(void))onConfirm;

/** 显示文本输入弹窗（完整版：默认文本 + 占位文本） */
+ (void)showTextInputAlert:(NSString *)title defaultText:(NSString *)defaultText placeholder:(NSString *)placeholder onConfirm:(void (^)(NSString *text))onConfirm onCancel:(void (^)(void))onCancel;

/** 显示文本输入弹窗（无占位符） */
+ (void)showTextInputAlert:(NSString *)title defaultText:(NSString *)defaultText onConfirm:(void (^)(NSString *text))onConfirm onCancel:(void (^)(void))onCancel;

/** 显示文本输入弹窗（简化版：仅标题） */
+ (void)showTextInputAlert:(NSString *)title onConfirm:(void (^)(NSString *text))onConfirm onCancel:(void (^)(void))onCancel;

/** 获取设置项依赖关系配置 */
+ (NSDictionary *)settingsDependencyConfig;

/** 应用依赖规则到设置项 */
+ (void)applyDependencyRulesForItem:(AWESettingItemModel *)item;

/** 处理设置项的冲突和依赖关系 */
+ (void)handleConflictsAndDependenciesForSetting:(NSString *)identifier isEnabled:(BOOL)isEnabled;

/** 更新冲突项的UI状态 */
+ (void)updateConflictingItemUIState:(NSString *)identifier withValue:(BOOL)value;

/** 更新依赖于指定设置项的所有设置项 */
+ (void)updateDependentItemsForSetting:(NSString *)identifier value:(id)value;

/** 创建设置项模型 */
+ (AWESettingItemModel *)createSettingItem:(NSDictionary *)dict;

/** 创建设置项模型（含单元格点击处理器） */
+ (AWESettingItemModel *)createSettingItem:(NSDictionary *)dict cellTapHandlers:(NSMutableDictionary *)cellTapHandlers;

/** 创建自定义图标设置项 */
+ (AWESettingItemModel *)createIconCustomizationItemWithIdentifier:(NSString *)identifier title:(NSString *)title svgIcon:(NSString *)svgIconName saveFile:(NSString *)saveFilename;

/** 创建设置分区 */
+ (AWESettingSectionModel *)createSectionWithTitle:(NSString *)title items:(NSArray *)items;

/** 创建设置分区，带 footer */
+ (AWESettingSectionModel *)createSectionWithTitle:(NSString *)title footerTitle:(NSString *)footerTitle items:(NSArray *)items;

/** 创建子设置页面控制器 */
+ (AWESettingBaseViewController *)createSubSettingsViewController:(NSString *)title sections:(NSArray *)sectionsArray;

/** 查找视图所在控制器 */
+ (UIViewController *)findViewController:(UIResponder *)responder;

/** 打开设置页 */
+ (void)openSettingsWithViewController:(UIViewController *)vc;

/** 从视图打开设置页 */
+ (void)openSettingsFromView:(UIView *)view;

/** 为视图添加打开设置页的点击手势 */
+ (void)addTapGestureToView:(UIView *)view target:(id)target;

/** 显示用户协议输入弹窗 */
+ (void)showUserAgreementAlert;

@end

FOUNDATION_EXPORT void showDYYYSettingsVC(UIViewController *rootVC, BOOL hasAgreed);
