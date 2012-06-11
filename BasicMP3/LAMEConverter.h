//
//  LAMEConverter.h
//  BasicMP3
//
//  Created by Alex Nichol on 6/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <ACPlugIn/ACConverter.h>

@interface LAMEConverter : ACConverter {
    NSTask * converterTask;
}

@end
