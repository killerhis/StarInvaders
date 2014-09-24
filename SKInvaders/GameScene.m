//
//  GameScene.m
//  Star Invaders
//

//  Copyright (c) 2013 RepublicOfApps, LLC. All rights reserved.
//

#import "GameScene.h"
#import <CoreMotion/CoreMotion.h>
#import <AVFoundation/AVFoundation.h>
#import "GAIDictionaryBuilder.h"

#pragma mark - Custom Type Definitions

typedef enum InvaderType {
    InvaderTypeA,
    InvaderTypeB,
    InvaderTypeC
} InvaderType;

typedef  enum InvaderMovementDirection {
    InvaderMovementDirectionRight,
    InvaderMovementDirectionLeft,
    InvaderMovementDirectionDownThenRight,
    InvaderMovementDirectionDownThenLeft,
    InvaderMovementDirectionNone
} InvaderMovementDirection;

typedef enum BulletType {
    ShipFiredBulletType,
    InvaderFiredBulletType
} BulletType;

static const u_int32_t kInvaderCategory = 0x1 << 0;
static const u_int32_t kShipFiredBulletCategory = 0x1 << 1;
static const u_int32_t kShipCategory = 0x1 << 2;
static const u_int32_t kSceneEdgeCategory = 0x1 << 3;
static const u_int32_t kInvaderFiredBulletCategory = 0x1 << 4;

#define kInvaderSize CGSizeMake(24,16)
#define kInvaderGridSpacing CGSizeMake(12,12)
#define kInvaderRowCount 6
#define kInvaderColCount 7

#define kInvaderName @"invader"

#define kShipSize CGSizeMake (30,16)
#define kShipName @"ship"

#define kScoreHudName @"scoreHud"
#define kHealthHudName @"healthHud"

#define kShipFiredBulletName @"shipFiredBullet"
#define kInvaderFiredBulletName @"invaderFiredBullet"
#define kBulletSize CGSizeMake(4,8)

#define kMinInvaderBottomHeight 2*kShipSize.height

#pragma mark - Private GameScene Properties

@interface GameScene ()

@property BOOL contentCreated;
@property InvaderMovementDirection invaderMovementDirection;

@property NSTimeInterval timeOfLastMove;
@property NSTimeInterval timePerMove;

@property NSTimeInterval timeOfLastBullet;
@property NSTimeInterval timePerShoot;

@property (strong) CMMotionManager *motionManager;
@property (strong) NSMutableArray *tapQueue;
@property (strong) NSMutableArray *contactQueue;

@property NSUInteger score;
@property CGFloat shipHealth;

@property BOOL gameEnding;
@property BOOL allowSpeedMove;

@property NSUserDefaults *defaults;

@property SKNode *backgroundMusic;

@property SKLabelNode *scoreLabel;

@end

@implementation GameScene {
    SKNode *restartGameScreenNode;
}

#pragma mark Object Lifecycle Management

#pragma mark - Scene Setup and Content Creation

- (void)didMoveToView:(SKView *)view
{
    if (!self.contentCreated) {
        
        [self createContent];
        self.contentCreated = YES;
        self.motionManager = [[CMMotionManager alloc] init];
        [self.motionManager startAccelerometerUpdates];
        
        self.tapQueue = [NSMutableArray array];
        self.userInteractionEnabled = YES;
        
        self.contactQueue = [NSMutableArray array];
        self.physicsWorld.contactDelegate = self;
        
        self.physicsBody = [SKPhysicsBody bodyWithEdgeLoopFromRect:self.frame];
        
        //For retrieving
        
        self.defaults = [NSUserDefaults standardUserDefaults];
        NSInteger playCount = [self.defaults integerForKey:@"playCount"];
        
        if (playCount == 0) {
            self.gameEnding = YES;
            [self.motionManager stopAccelerometerUpdates];
            [self startGameScreen];
            
            [self enumerateChildNodesWithName:kScoreHudName usingBlock:^(SKNode *node, BOOL *stop) {
                
                node.position = CGPointMake(self.size.width/2, self.size.height+node.frame.size.height*2);
                
            }];
        } else {
            // GA
            id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
            [tracker set:kGAIScreenName value:@"PlayGameScene"];
            [tracker send:[[GAIDictionaryBuilder createAppView] build]];
        }
        
        playCount++;
        [self.defaults setInteger:playCount forKey:@"playCount"];
        [self.defaults synchronize];
        
    }
}

- (void)createContent
{
    self.invaderMovementDirection = InvaderMovementDirectionRight;
    self.timePerMove = 1.0;
    self.timeOfLastMove = 0.0;
    self.timePerShoot = 1.0;
    self.timeOfLastBullet = 0.0;
    self.allowSpeedMove = NO;
    
    self.physicsBody.categoryBitMask = kSceneEdgeCategory;
    
    [self setupInvaders];
    [self setupShip];
    [self setupHud];
}

- (NSArray *)loadInvaderTexturesOfType:(InvaderType)invaderType
{
    NSString *prefix;
    
    switch (invaderType) {
        case InvaderTypeA:
            prefix = @"InvaderA";
            break;
        case InvaderTypeB:
            prefix = @"InvaderB";
            break;
        case InvaderTypeC:
        default:
            prefix = @"InvaderC";
            break;
    }
    
    return @[[SKTexture textureWithImageNamed:[NSString stringWithFormat:@"%@_00.png", prefix]],[SKTexture textureWithImageNamed:[NSString stringWithFormat:@"%@_01.png", prefix]]];
}

- (SKNode *)makeInvaderOfType:(InvaderType)invaderType
{
    NSArray *invaderTextures = [self loadInvaderTexturesOfType:invaderType];
    
    SKSpriteNode *invader = [SKSpriteNode spriteNodeWithTexture:[invaderTextures firstObject]];

    invader.name = kInvaderName;
    
    [invader runAction:[SKAction repeatActionForever:[SKAction animateWithTextures:invaderTextures timePerFrame:self.timePerMove]]];
    
    invader.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:invader.frame.size];
    invader.physicsBody.dynamic = NO;
    invader.physicsBody.categoryBitMask = kInvaderCategory;
    invader.physicsBody.contactTestBitMask = 0x0;
    invader.physicsBody.collisionBitMask = 0x0;
    
    return invader;
}

- (void)setupInvaders
{
    float invaderColWidth = kInvaderColCount*kInvaderSize.width + kInvaderGridSpacing.width*(kInvaderColCount-1);
    float baseOriginWidth = (self.size.width - invaderColWidth)/2 + kInvaderSize.width/2;

    CGPoint baseOrigin = CGPointMake(baseOriginWidth,self.size.height/2);
    
    for (NSUInteger row = 0; row < kInvaderRowCount; row++)
    {
        InvaderType invaderType;
        
        if (row % 3 ==0) {
            invaderType = InvaderTypeA;
        } else if (row % 3 == 1) {
            invaderType = InvaderTypeB;
        } else {
            invaderType = InvaderTypeC;
        }
        
        CGPoint invaderPosition = CGPointMake(baseOrigin.x, row * (kInvaderGridSpacing.height + kInvaderSize.height) + baseOrigin.y);
        //NSLog(@"%f", baseOrigin.x);
        
        for (NSInteger col = 0; col < kInvaderColCount; col++)
        {
            SKNode *invader = [self makeInvaderOfType:invaderType];
            invader.position = invaderPosition;
            invader.alpha = 0.0f;
            [invader runAction:[SKAction fadeAlphaTo:1.0f duration:0.5]];
            [self addChild:invader];
            
            invaderPosition.x += kInvaderSize.width + kInvaderGridSpacing.width;
        }
    }
}

- (void)setupShip
{
    SKNode *ship = [self makeShip];
    
    ship.position = CGPointMake(self.size.width / 2.0f, kShipSize.height/2.0f + self.size.height/16);
    self.shipHealth = 1.0f;
    [self addChild:ship];
}

- (SKNode *)makeShip
{
    
    SKSpriteNode *ship = [SKSpriteNode spriteNodeWithImageNamed:@"Ship.png"];
    ship.name = kShipName;
    
    ship.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:ship.frame.size];
    ship.physicsBody.dynamic = YES;
    ship.physicsBody.affectedByGravity = NO;
    ship.physicsBody.mass = 0.01;
    
    ship.physicsBody.categoryBitMask = kShipCategory;
    ship.physicsBody.contactTestBitMask = 0x0;
    ship.physicsBody.collisionBitMask = kSceneEdgeCategory;
    
    return ship;
}

- (void)setupHud
{
    self.scoreLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    
    self.scoreLabel.name = kScoreHudName;
    self.scoreLabel.fontSize = 30;
    
    self.scoreLabel.fontColor = [SKColor whiteColor];
    self.scoreLabel.text = [NSString stringWithFormat:@"%i", 0];
    
    self.scoreLabel.position = CGPointMake(self.size.width/2, self.size.height - (20 + self.scoreLabel.frame.size.height/2) - self.size.height/16);
    
    [self addChild:self.scoreLabel];
    
}

- (SKNode *)makeBulletOfType:(BulletType)bulletType
{
    SKNode *bullet;
    
    switch (bulletType) {
        case ShipFiredBulletType:
            bullet = [SKSpriteNode spriteNodeWithColor:[SKColor redColor] size:kBulletSize];
            bullet.name = kShipFiredBulletName;
            
            bullet.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:bullet.frame.size];
            bullet.physicsBody.dynamic = YES;
            bullet.physicsBody.affectedByGravity = NO;
            bullet.physicsBody.categoryBitMask = kShipFiredBulletCategory;
            bullet.physicsBody.contactTestBitMask = kInvaderCategory;
            bullet.physicsBody.collisionBitMask = 0x0;
            break;
        case InvaderFiredBulletType:
            bullet = [SKSpriteNode spriteNodeWithColor:[SKColor whiteColor] size:kBulletSize];
            bullet.name = kInvaderFiredBulletName;
            
            bullet.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:bullet.frame.size];
            bullet.physicsBody.dynamic = YES;
            bullet.physicsBody.affectedByGravity = NO;
            bullet.physicsBody.categoryBitMask = kInvaderFiredBulletCategory;
            bullet.physicsBody.contactTestBitMask = kShipCategory;
            bullet.physicsBody.collisionBitMask = 0x0;
            break;
        default:
            bullet = nil;
            break;
    }
    
    return bullet;
}

#pragma mark - Scene Update

- (void)update:(NSTimeInterval)currentTime
{
    [self processUserMotionForUpdate:currentTime];
    [self moveInvadersForUpdate:currentTime];
    [self processUserTapsForUpdate:currentTime];
    [self fireInvaderBulletsForUpdate:currentTime];
    [self processContactsForUpdate:currentTime];
    [self adjustInvaderMovementToTimePerMove];
    
    if ([self isGameOver]) {
        [self endGame];
    }
}

#pragma mark - Scene Update Helpers

- (void)moveInvadersForUpdate:(NSTimeInterval)currentTime
{
    if (currentTime - self.timeOfLastMove < self.timePerMove) {
        return;
    }
    
    if (!self.gameEnding) {
        [self determineInvaderMovementDirection];
        
        [self enumerateChildNodesWithName:kInvaderName usingBlock:^(SKNode *node, BOOL *stop) {
            switch (self.invaderMovementDirection) {
                case InvaderMovementDirectionRight:
                    node.position = CGPointMake(node.position.x + 10, node.position.y);
                    break;
                case InvaderMovementDirectionLeft:
                    node.position = CGPointMake(node.position.x - 10, node.position.y);
                    break;
                case InvaderMovementDirectionDownThenLeft:
                case InvaderMovementDirectionDownThenRight:
                    node.position = CGPointMake(node.position.x, node.position.y - 10);
                    break;
                case InvaderMovementDirectionNone:
                default:
                    break;
            }
        }];
        
        self.timeOfLastMove = currentTime;
    }
}

- (void)processUserMotionForUpdate:(NSTimeInterval)currentTime
{
    SKSpriteNode *ship = (SKSpriteNode *)[self childNodeWithName:kShipName];
    CMAccelerometerData *data = self.motionManager.accelerometerData;
    
    ship.physicsBody.velocity = CGVectorMake(1000*data.acceleration.x, 0);
    ship.zRotation = 0;
}

- (void)processUserTapsForUpdate:(NSTimeInterval)currentTime
{
    for (NSNumber *tapCount in [self.tapQueue copy]) {
        //if ([tapCount unsignedIntegerValue] == 1) {
        if ([tapCount unsignedIntegerValue] >= 1) {
            [self fireShipBullets];
            [self.tapQueue removeObject:tapCount];
        }
    }
}

- (void)fireInvaderBulletsForUpdate:(NSTimeInterval)currentTime
{
    
    if (currentTime - self.timeOfLastBullet > self.timePerShoot && !self.gameEnding) {
        
        NSMutableArray *allInvaders = [NSMutableArray array];
        [self enumerateChildNodesWithName:kInvaderName usingBlock:^(SKNode *node, BOOL *stop) {
            [allInvaders addObject:node];
        }];
        
        if ([allInvaders count] > 0) {
            NSUInteger allInvadersInxed = arc4random_uniform((u_int32_t)[allInvaders count]);
            SKNode *invader = [allInvaders objectAtIndex:allInvadersInxed];
            
            SKNode *bullet = [self makeBulletOfType:InvaderFiredBulletType];
            bullet.position = CGPointMake(invader.position.x, invader.position.y - invader.frame.size.height/2 + bullet.frame.size.height /2);
            
            CGPoint bulletDestination = CGPointMake(invader.position.x, - bullet.frame.size.height/2);
            
            [self fireBullet:bullet toDestination:bulletDestination withDuration:2.0 soundFileName:@"InvaderBullet.caf"];
        }
        
        self.timeOfLastBullet = currentTime;
    }
}

- (void)processContactsForUpdate:(NSTimeInterval)currentTime
{
    for (SKPhysicsContact *contact in [self.contactQueue copy])
    {
        [self handleContact:contact];
        [self.contactQueue removeObject:contact];
        
    }
}

#pragma mark - Invader Movement Helpers

- (void)determineInvaderMovementDirection
{
    __block InvaderMovementDirection proposedMovementDirection = self.invaderMovementDirection;
    
    [self enumerateChildNodesWithName:kInvaderName usingBlock:^(SKNode *node, BOOL *stop) {
        switch (self.invaderMovementDirection) {
            case InvaderMovementDirectionRight:
                
                if (CGRectGetMaxX(node.frame) >= node.scene.size.width - 1.0f) {
                    proposedMovementDirection = InvaderMovementDirectionDownThenLeft;
                    *stop = YES;
                }
                break;
            case InvaderMovementDirectionLeft:
                
                if (CGRectGetMinX(node.frame) <= 1.0f) {
                    proposedMovementDirection = InvaderMovementDirectionDownThenRight;
                    *stop = YES;
                }
                break;
            case InvaderMovementDirectionDownThenLeft:
            
                    proposedMovementDirection = InvaderMovementDirectionLeft;
                    //[self adjustInvaderMovementToTimePerMove];
                    *stop = YES;
                break;
            case InvaderMovementDirectionDownThenRight:
                
                    proposedMovementDirection = InvaderMovementDirectionRight;
                    //[self adjustInvaderMovementToTimePerMove];
                    *stop = YES;
                break;
            default:
                break;
        }
     }];
    
    if (proposedMovementDirection != self.invaderMovementDirection) {
        self.invaderMovementDirection = proposedMovementDirection;
    }
}

- (void)adjustInvaderMovementToTimePerMove
{
    if (self.timePerMove > 0.01 && self.score % 10 == 0 && self.allowSpeedMove)
    {
        self.allowSpeedMove = NO;
        double ratio = self.timePerMove * (1 / 0.9);
        self.timePerMove = self.timePerMove * 0.9;
        self.timePerShoot = self.timePerShoot*0.8;
        
        [self enumerateChildNodesWithName:kInvaderName usingBlock:^(SKNode *node, BOOL *stop) {
            node.speed = node.speed * ratio;
        }];
    }
}

#pragma mark - Bullet Helpers

- (void)fireBullet:(SKNode *)bullet toDestination:(CGPoint)destination withDuration:(NSTimeInterval)duration soundFileName:(NSString *)soundFileName
{
    //SKAction *bulletAction = [SKAction sequence:@[[SKAction moveTo:destination duration:duration], [SKAction waitForDuration:3.0/60.0], [SKAction removeFromParent]]];
    SKAction *bulletAction = [SKAction sequence:@[[SKAction moveTo:destination duration:duration], [SKAction waitForDuration:3.0/60.0]]];
    SKAction *soundAction = [SKAction playSoundFileNamed:soundFileName waitForCompletion:YES];
    
    //[bullet runAction:[SKAction group:@[bulletAction, soundAction]]];
    [bullet runAction:[SKAction group:@[bulletAction, soundAction]] completion:^{
        [bullet removeFromParent];
        [self removeFromParent];
    }];
    
    [self addChild:bullet];
}

- (void)fireShipBullets
{
        SKNode *ship = [self childNodeWithName:kShipName];
        SKNode *bullet = [self makeBulletOfType:ShipFiredBulletType];
        
        bullet.position = CGPointMake(ship.position.x, ship.position.y + ship.frame.size.height - bullet.frame.size.height/2);
        CGPoint bulletDestination = CGPointMake(ship.position.x, self.frame.size.height + bullet.frame.size.height/2);
        
        [self fireBullet:bullet toDestination:bulletDestination withDuration:1.0 soundFileName:@"ShipBullet.caf"];
}

#pragma mark - User Tap Helpers

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInNode:self];
    SKNode *node = [self nodeAtPoint:location];
    
    if (!self.gameEnding) {
        [self.tapQueue addObject:@1];
    } else {
        
        if ([node.name isEqualToString:@"playButtonNode"]) {
            
            [restartGameScreenNode runAction:[SKAction moveToY:self.size.height duration:0.5]];
            
            GameScene* gameScene = [[GameScene alloc] initWithSize:self.size];
            gameScene.scaleMode = SKSceneScaleModeAspectFill;
            [self.view presentScene:gameScene transition:[SKTransition fadeWithColor:[SKColor blackColor] duration:1.0]];
            
        } else if ([node.name isEqualToString:@"startPlayButtonNode"]) {
            [self.motionManager startAccelerometerUpdates];
            self.gameEnding = NO;
            [self enumerateChildNodesWithName:@"startGameScreenNode" usingBlock:^(SKNode *node, BOOL *stop) {
                
                [node runAction:[SKAction moveToY:self.size.height duration:0.5]];
  
            }];
            
            [self enumerateChildNodesWithName:kScoreHudName usingBlock:^(SKNode *node, BOOL *stop) {
                
                [node runAction:[SKAction moveToY:self.size.height - (20 + self.scoreLabel.frame.size.height/2) - self.size.height/16 duration:0.5]];
                
            }];
            
        }
    }
}

#pragma mark - HUD Helpers

- (void)adjustScoreBy:(NSUInteger)points
{
    self.score += points;
    SKLabelNode *score = (SKLabelNode *)[self childNodeWithName:kScoreHudName];
    score.text = [NSString stringWithFormat:@"%i", (int)self.score];
}

- (void)adjustShipHealthBy:(CGFloat)healthAdjustment
{
    self.shipHealth = MAX(self.shipHealth + healthAdjustment, 0);
    
    SKLabelNode *health = (SKLabelNode *)[self childNodeWithName:kHealthHudName];
    health.text = [NSString stringWithFormat:@"Health: %.1f%%", self.shipHealth * 100];
}

#pragma mark - Physics Contact Helpers

- (void)didBeginContact:(SKPhysicsContact *)contact
{
    [self.contactQueue addObject:contact];
}

- (void)handleContact:(SKPhysicsContact *)contact
{
    if (!contact.bodyA.node.parent || !contact.bodyB.node.parent) {
        return;
    }
    
    NSArray *nodeNames = @[contact.bodyA.node.name, contact.bodyB.node.name];
    
    if ([nodeNames containsObject:kShipName] && [nodeNames containsObject:kInvaderFiredBulletName]) {
        
        [self runAction:[SKAction playSoundFileNamed:@"ShipHit.caf" waitForCompletion:NO]];
        
        [self adjustShipHealthBy:-1.0f];
        
        if (self.shipHealth <=0.0f) {
            
            [contact.bodyA.node removeFromParent];
            [contact.bodyB.node removeFromParent];
        } else {
            
            SKNode *ship = [self childNodeWithName:kShipName];
            ship.alpha = self.shipHealth;
            
            if (contact.bodyA.node == ship) {
                [contact.bodyB.node removeFromParent];
            } else {
                [contact.bodyA.node removeFromParent];
            }
        }
    } else if ([nodeNames containsObject:kInvaderName] && [nodeNames containsObject:kShipFiredBulletName]) {
        
        [self runAction:[SKAction playSoundFileNamed:@"InvaderHit.caf" waitForCompletion:NO]];
        //[contact.bodyA.node removeFromParent];
        //[contact.bodyB.node removeFromParent];
        
        [contact.bodyA.node removeFromParent];
        [contact.bodyB.node removeFromParent];
        [self removeFromParent];
        
        [self adjustScoreBy:1];
        self.allowSpeedMove = YES;
    }
}

#pragma mark - Game End Helpers

- (BOOL)isGameOver
{
    SKNode *invader = [self childNodeWithName:kInvaderName];
    
    __block BOOL invaderTooLow = NO;
    [self enumerateChildNodesWithName:kInvaderName usingBlock:^(SKNode *node, BOOL *stop) {
        if (CGRectGetMinY(node.frame) <= kMinInvaderBottomHeight) {
            invaderTooLow = YES;
            *stop = YES;
        }
    }];
    
    
    if (!invader) {
        [self setupInvaders];
    }
    
    SKNode *ship = [self childNodeWithName:kShipName];
    
    return invaderTooLow || !ship;
    //return YES;
}

- (void)endGame
{
    if (!self.gameEnding) {
        self.gameEnding = YES;
        
        [self.motionManager stopAccelerometerUpdates];
        
        NSInteger bestScore = [self.defaults integerForKey:@"bestScore"];
        
        if (self.score > bestScore) {
            
            [self.defaults setInteger:self.score forKey:@"bestScore"];
            [self.defaults synchronize];
        }
        
        // show game over screen
        
        [self restartGameScreen];
        
        [self enumerateChildNodesWithName:kScoreHudName usingBlock:^(SKNode *node, BOOL *stop) {
            
            [node runAction:[SKAction moveToY:self.size.height+100 duration:0.5]];
        }];
    }
}

#pragma mark - Game Screens

- (void)startGameScreen
{
    // GA
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker set:kGAIScreenName value:@"StartGameScene"];
    [tracker send:[[GAIDictionaryBuilder createAppView] build]];
    
    SKNode *startGameScreen = [[SKNode alloc] init];//
    
    SKLabelNode* gameOverLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    gameOverLabel.fontSize = 27;
    gameOverLabel.fontColor = [SKColor whiteColor];
    gameOverLabel.text = @"Star Invaders";
    
    
    SKTexture *playButtonTexture = [SKTexture textureWithImageNamed:@"play_button.png"];
    playButtonTexture.filteringMode = SKTextureFilteringNearest;
    SKSpriteNode *playButtonNode = [SKSpriteNode spriteNodeWithTexture:playButtonTexture size:CGSizeMake(playButtonTexture.size.width*3, playButtonTexture.size.height*3)];
    playButtonNode.position = CGPointMake(self.size.width/2, playButtonNode.size.height/2 + self.size.height/16);
    playButtonNode.name = @"startPlayButtonNode";
    [startGameScreen addChild:playButtonNode];
    
    
    float StartLabelHeight = self.size.height/2 + (kInvaderSize.height*kInvaderRowCount) + (kInvaderGridSpacing.height*kInvaderRowCount);
    
    gameOverLabel.position = CGPointMake(self.size.width/2, StartLabelHeight);
    [startGameScreen addChild:gameOverLabel];
    
    SKLabelNode* tapLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    tapLabel.fontSize = 25;
    tapLabel.fontColor = [SKColor whiteColor];
    tapLabel.text = @"Start!";
    tapLabel.position = CGPointMake(self.size.width/2, self.size.height/8 + playButtonTexture.size.height*3);
    [startGameScreen addChild:tapLabel];
    
    
    startGameScreen.name = @"startGameScreenNode";
    
    [self addChild:startGameScreen];
}

- (void)restartGameScreen
{
    // GA
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker set:kGAIScreenName value:@"GameOverScene"];
    [tracker send:[[GAIDictionaryBuilder createAppView] build]];
    
    restartGameScreenNode = [[SKNode alloc] init];
    
    SKLabelNode* gameOverLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    gameOverLabel.fontSize = 40;
    gameOverLabel.fontColor = [SKColor whiteColor];
    gameOverLabel.text = @"game over";
    gameOverLabel.position = CGPointMake(self.size.width/2, self.size.height - self.size.height/8);
    [restartGameScreenNode addChild:gameOverLabel];
    
    SKLabelNode* bestScoreLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    bestScoreLabel.fontSize = 15;
    bestScoreLabel.fontColor = [SKColor whiteColor];
    bestScoreLabel.text = @"best score";
    bestScoreLabel.position = CGPointMake(self.size.width/2, gameOverLabel.frame.origin.y - gameOverLabel.frame.size.height - 40);
    bestScoreLabel.zPosition = 20;
    [restartGameScreenNode addChild:bestScoreLabel];
    
    SKLabelNode* bestScoreValueLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    bestScoreValueLabel.fontSize = 30;
    bestScoreValueLabel.fontColor = [SKColor whiteColor];
    bestScoreValueLabel.text = [NSString stringWithFormat:@"%i", (int)[self.defaults integerForKey:@"bestScore"]];
    bestScoreValueLabel.position = CGPointMake(self.size.width/2, gameOverLabel.frame.origin.y - gameOverLabel.frame.size.height - 80);
    bestScoreValueLabel.zPosition = 20;
    [restartGameScreenNode addChild:bestScoreValueLabel];
    
    SKLabelNode* restartScoreLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    restartScoreLabel.fontSize = 10;
    restartScoreLabel.fontColor = [SKColor whiteColor];
    restartScoreLabel.text = @"score";
    restartScoreLabel.position = CGPointMake(self.size.width/2, gameOverLabel.frame.origin.y - gameOverLabel.frame.size.height - 160);
    restartScoreLabel.zPosition = 20;
    [restartGameScreenNode addChild:restartScoreLabel];
    
    SKLabelNode* scoreValueLabel = [SKLabelNode labelNodeWithFontNamed:@"MineCrafter 3"];
    scoreValueLabel.fontSize = 20;
    scoreValueLabel.fontColor = [SKColor whiteColor];
    scoreValueLabel.text = [NSString stringWithFormat:@"%i", (int)self.score];
    scoreValueLabel.position = CGPointMake(self.size.width/2, gameOverLabel.frame.origin.y - gameOverLabel.frame.size.height - 190);
    scoreValueLabel.zPosition = 20;
    [restartGameScreenNode addChild:scoreValueLabel];
    
    SKSpriteNode *scoreBackground = [SKSpriteNode spriteNodeWithColor:[SKColor colorWithRed:38.0/255.0 green:38.0/255.0 blue:38.0/255.0 alpha:1.0] size:CGSizeMake(bestScoreLabel.frame.size.width + 50, 200)];
    scoreBackground.position = CGPointMake(self.size.width/2, gameOverLabel.frame.origin.y - gameOverLabel.frame.size.height - 105);
    scoreBackground.zPosition = 10;
    [restartGameScreenNode addChild:scoreBackground];
    
    SKTexture *playButtonTexture = [SKTexture textureWithImageNamed:@"play_button.png"];
    playButtonTexture.filteringMode = SKTextureFilteringNearest;
    SKSpriteNode *playButtonNode = [SKSpriteNode spriteNodeWithTexture:playButtonTexture size:CGSizeMake(playButtonTexture.size.width*3, playButtonTexture.size.height*3)];
    playButtonNode.position = CGPointMake(self.size.width/2, playButtonNode.size.height/2 + self.size.height/16);
    playButtonNode.name = @"playButtonNode";
    [restartGameScreenNode addChild:playButtonNode];
    
    restartGameScreenNode.position = CGPointMake(0, self.size.height);
    
    [restartGameScreenNode runAction:[SKAction moveToY:0 duration:0.5]];
    
    [self addChild:restartGameScreenNode];
}
@end
