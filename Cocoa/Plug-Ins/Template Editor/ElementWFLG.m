#import "ElementWFLG.h"
#import "ElementBFLG.h"

@implementation ElementWFLG

- (void)configureView:(NSView *)view
{
    [view addSubview:[ElementBFLG createCheckboxWithFrame:view.frame forElement:self]];
}

@end
