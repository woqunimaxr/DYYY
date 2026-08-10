#import "DYYYMediaChooserSheet.h"
#import "DYYYUtils.h"

static const CGFloat kDYYYChooserRowHeight = 56.0;
static const CGFloat kDYYYChooserCancelHeight = 56.0;
static const CGFloat kDYYYChooserGroupGap = 8.0;
static const CGFloat kDYYYChooserCornerRadius = 12.0;
/** 弹窗整体高度上限占窗口高度的比例，超出后条目区域改为滚动。 */
static const CGFloat kDYYYChooserMaxHeightRatio = 0.5;

@implementation DYYYMediaChooserItem

+ (instancetype)itemWithTitle:(NSString *)title handler:(void (^)(void))handler {
    DYYYMediaChooserItem *item = [[DYYYMediaChooserItem alloc] init];
    if (item) {
        item->_title = [title copy];
        item->_handler = [handler copy];
    }
    return item;
}

@end

@interface DYYYMediaChooserSheet () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) UIView *dimmingView;
@property(nonatomic, strong) UIView *containerView;
@property(nonatomic, strong) UIView *actionsCard;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UIView *cancelCard;
@property(nonatomic, strong) UIButton *cancelButton;
@property(nonatomic, copy) NSArray<DYYYMediaChooserItem *> *items;
@property(nonatomic, assign) BOOL dismissing;

@end

@implementation DYYYMediaChooserSheet

+ (void)showWithItems:(NSArray<DYYYMediaChooserItem *> *)items {
    if (items.count == 0) {
        return;
    }

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self showWithItems:items];
        });
        return;
    }

    UIWindow *window = [DYYYUtils getActiveWindow] ?: UIApplication.sharedApplication.windows.firstObject;
    if (!window) {
        return;
    }

    DYYYMediaChooserSheet *sheet = [[DYYYMediaChooserSheet alloc] initWithItems:items];
    [window addSubview:sheet];
    sheet.frame = window.bounds;
    [sheet layoutIfNeeded];
    [sheet presentAnimated];
}

- (instancetype)initWithItems:(NSArray<DYYYMediaChooserItem *> *)items {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _items = [items copy];
        self.backgroundColor = [UIColor clearColor];
        [self buildSubviews];
        [self applyThemeColors];
    }
    return self;
}

- (void)buildSubviews {
    _dimmingView = [[UIView alloc] init];
    _dimmingView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    _dimmingView.alpha = 0.0;
    [self addSubview:_dimmingView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDimmingTap)];
    [_dimmingView addGestureRecognizer:tap];

    _containerView = [[UIView alloc] init];
    _containerView.backgroundColor = [UIColor clearColor];
    [self addSubview:_containerView];

    _actionsCard = [[UIView alloc] init];
    _actionsCard.layer.cornerRadius = kDYYYChooserCornerRadius;
    _actionsCard.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _actionsCard.clipsToBounds = YES;
    [_containerView addSubview:_actionsCard];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = kDYYYChooserRowHeight;
    _tableView.separatorInset = UIEdgeInsetsZero;
    _tableView.tableFooterView = [[UIView alloc] init];
    _tableView.showsVerticalScrollIndicator = YES;
    _tableView.alwaysBounceVertical = NO;
    if (@available(iOS 15.0, *)) {
        _tableView.sectionHeaderTopPadding = 0.0;
    }
    [_actionsCard addSubview:_tableView];

    _cancelCard = [[UIView alloc] init];
    _cancelCard.layer.cornerRadius = kDYYYChooserCornerRadius;
    _cancelCard.clipsToBounds = YES;
    [_containerView addSubview:_cancelCard];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    [_cancelButton addTarget:self action:@selector(handleCancelTap) forControlEvents:UIControlEventTouchUpInside];
    [_cancelCard addSubview:_cancelButton];
}

- (void)applyThemeColors {
    UIColor *cardColor = [DYYYUtils douyinPanelBackgroundColor];
    UIColor *separatorColor = [DYYYUtils douyinSeparatorColor];
    UIColor *textColor = [DYYYUtils isDarkMode] ? [UIColor whiteColor] : [UIColor blackColor];

    self.actionsCard.backgroundColor = cardColor;
    self.cancelCard.backgroundColor = cardColor;
    self.tableView.backgroundColor = cardColor;
    self.tableView.separatorColor = separatorColor;
    [self.cancelButton setTitleColor:textColor forState:UIControlStateNormal];
    [self.tableView reloadData];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];

    self.dimmingView.frame = self.bounds;

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat bottomInset = 0.0;
    if (@available(iOS 11.0, *)) {
        bottomInset = self.safeAreaInsets.bottom;
    }

    // 高度按窗口比例算、底部留安全区，各机型自动适配，无需按屏幕尺寸分支。
    CGFloat maxSheetHeight = CGRectGetHeight(self.bounds) * kDYYYChooserMaxHeightRatio;
    CGFloat reservedHeight = kDYYYChooserCancelHeight + kDYYYChooserGroupGap + bottomInset;
    CGFloat maxTableHeight = MAX(kDYYYChooserRowHeight, maxSheetHeight - reservedHeight);
    CGFloat naturalTableHeight = kDYYYChooserRowHeight * (CGFloat)self.items.count;
    CGFloat tableHeight = MIN(naturalTableHeight, maxTableHeight);
    self.tableView.scrollEnabled = naturalTableHeight > tableHeight;

    CGFloat containerHeight = tableHeight + reservedHeight;
    self.containerView.frame = CGRectMake(0.0, CGRectGetHeight(self.bounds) - containerHeight, width, containerHeight);
    self.actionsCard.frame = CGRectMake(0.0, 0.0, width, tableHeight);
    self.tableView.frame = self.actionsCard.bounds;
    self.cancelCard.frame = CGRectMake(0.0, tableHeight + kDYYYChooserGroupGap, width, kDYYYChooserCancelHeight);
    self.cancelButton.frame = self.cancelCard.bounds;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyThemeColors];
        }
    }
}

#pragma mark - 转场

- (void)presentAnimated {
    CGFloat offset = MAX(CGRectGetHeight(self.containerView.frame), 1.0);
    self.containerView.transform = CGAffineTransformMakeTranslation(0.0, offset);

    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.16 : 0.28;
    [UIView animateWithDuration:duration
                          delay:0.0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                       self.dimmingView.alpha = 1.0;
                       self.containerView.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];
}

- (void)dismissAnimatedWithCompletion:(void (^)(void))completion {
    if (self.dismissing) {
        return;
    }
    self.dismissing = YES;

    CGFloat offset = MAX(CGRectGetHeight(self.containerView.frame), 1.0);
    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.12 : 0.22;
    [UIView animateWithDuration:duration
        delay:0.0
        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
        animations:^{
          self.dimmingView.alpha = 0.0;
          self.containerView.transform = CGAffineTransformMakeTranslation(0.0, offset);
        }
        completion:^(BOOL finished) {
          [self removeFromSuperview];
          if (completion) {
              completion();
          }
        }];
}

- (void)handleDimmingTap {
    [self dismissAnimatedWithCompletion:nil];
}

- (void)handleCancelTap {
    [self dismissAnimatedWithCompletion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const cellIdentifier = @"DYYYMediaChooserCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }

    DYYYMediaChooserItem *item = self.items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item.title;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.textLabel.textColor = [DYYYUtils isDarkMode] ? [UIColor whiteColor] : [UIColor blackColor];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ((NSUInteger)indexPath.row >= self.items.count) {
        return;
    }
    void (^handler)(void) = self.items[(NSUInteger)indexPath.row].handler;

    // 先收起弹窗再执行，避免下载进度浮层被弹窗遮住。
    [self dismissAnimatedWithCompletion:^{
      if (handler) {
          handler();
      }
    }];
}

@end
