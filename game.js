'use strict';

// ─── Constants ────────────────────────────────────────────────────────────────

const MAP_W = 1800;
const MAP_H = 1200;
const PLAYER_SPEED = 200;

const SHOP = {
  x: 80,
  y: 80,
  w: 240,
  h: 180,
  get doorX() { return this.x + this.w / 2 - 24; },
  doorW: 48,
};

// ─── Phaser Config ────────────────────────────────────────────────────────────

const config = {
  type: Phaser.AUTO,
  width: 800,
  height: 600,
  physics: {
    default: 'arcade',
    arcade: { gravity: { y: 0 }, debug: false },
  },
  scene: { preload, create, update },
};

const game = new Phaser.Game(config);

// ─── Scene Globals ────────────────────────────────────────────────────────────

let player, playerBody;
let cursors, wasd;
let walls;
let isInsideShop = true;
let darkOverlay;
let statusText;

// ─── Scene Lifecycle ──────────────────────────────────────────────────────────

function preload() {}

function create() {
  const scene = this;

  scene.physics.world.setBounds(0, 0, MAP_W, MAP_H);

  drawMap(scene);
  addMapLabels(scene);

  walls = scene.physics.add.staticGroup();
  buildShopWalls(scene);
  buildEnvColliders(scene);

  // Player (placeholder rect)
  player = scene.add.rectangle(
    SHOP.x + SHOP.w / 2,
    SHOP.y + SHOP.h - 24,
    16, 22, 0xffe066
  ).setDepth(10);
  scene.physics.add.existing(player);
  playerBody = player.body;
  playerBody.setCollideWorldBounds(true);
  scene.physics.add.collider(player, walls);

  // Dark overlay — fixed to camera, covers screen
  darkOverlay = scene.add.rectangle(0, 0, 800, 600, 0x04040f, 0)
    .setOrigin(0)
    .setScrollFactor(0)
    .setDepth(50);

  // HUD
  statusText = scene.add.text(12, 12, '', {
    fontFamily: 'monospace',
    fontSize: '13px',
    color: '#ffcc88',
    backgroundColor: '#00000099',
    padding: { x: 8, y: 5 },
  }).setScrollFactor(0).setDepth(100);

  // Camera
  scene.cameras.main.setBounds(0, 0, MAP_W, MAP_H);
  scene.cameras.main.startFollow(player, true, 0.08, 0.08);
  scene.cameras.main.setBackgroundColor('#0d0802');

  // Input
  cursors = scene.input.keyboard.createCursorKeys();
  wasd    = scene.input.keyboard.addKeys('W,A,S,D');

  setAtmosphere(scene, true, true);
}

function update() {
  const scene = this;
  handleMovement();
  checkZone(scene);
}

// ─── Movement ─────────────────────────────────────────────────────────────────

function handleMovement() {
  let vx = 0, vy = 0;

  if      (cursors.left.isDown  || wasd.A.isDown) vx = -PLAYER_SPEED;
  else if (cursors.right.isDown || wasd.D.isDown) vx =  PLAYER_SPEED;
  if      (cursors.up.isDown    || wasd.W.isDown) vy = -PLAYER_SPEED;
  else if (cursors.down.isDown  || wasd.S.isDown) vy =  PLAYER_SPEED;

  if (vx && vy) { vx *= 0.707; vy *= 0.707; }
  playerBody.setVelocity(vx, vy);
}

// ─── Zone Detection ───────────────────────────────────────────────────────────

function checkZone(scene) {
  const px = player.x, py = player.y;
  const inside =
    px > SHOP.x + 12 && px < SHOP.x + SHOP.w - 12 &&
    py > SHOP.y + 12 && py < SHOP.y + SHOP.h - 12;

  if (inside !== isInsideShop) {
    isInsideShop = inside;
    setAtmosphere(scene, inside, false);
  }
}

// ─── Atmosphere ───────────────────────────────────────────────────────────────

function setAtmosphere(scene, inside, instant) {
  const dur = instant ? 0 : 750;

  scene.tweens.add({
    targets: darkOverlay,
    alpha: inside ? 0 : 0.68,
    duration: dur,
    ease: 'Power2',
  });

  scene.cameras.main.zoomTo(inside ? 1.3 : 1.0, dur, 'Power2');

  const color = inside ? '#ffcc88' : '#8899cc';
  const loc   = inside ? '[ INSIDE — THE SHOP ]'       : '[ OUTSIDE — MONSTERVILLE ]';
  const music = inside ? '♪  lofi / cozy'               : '♫  ambient dread...';
  statusText.setText(`${loc}\n${music}`).setColor(color);
}

// ─── Map Drawing ──────────────────────────────────────────────────────────────

function drawMap(scene) {
  const g = scene.add.graphics();

  // Base ground
  g.fillStyle(0x12121c, 1);
  g.fillRect(0, 0, MAP_W, MAP_H);

  // Sidewalk blocks (slightly lighter than streets)
  g.fillStyle(0x1c1c2c, 1);
  [
    [0,    0,   400, 330],
    [490,  0,   330, 330],
    [910,  0,   330, 330],
    [1330, 0,   470, 330],
    [0,    420, 400, 260],
    [490,  420, 330, 260],
    [910,  420, 330, 260],
    [1330, 420, 470, 260],
  ].forEach(([x, y, w, h]) => g.fillRect(x, y, w, h));

  // Streets
  g.fillStyle(0x18181f, 1);
  g.fillRect(0,    330, MAP_W, 90);   // H street
  g.fillRect(0,    680, MAP_W, 90);   // H street 2
  g.fillRect(400,  0,   90, MAP_H);   // V street 1
  g.fillRect(820,  0,   90, MAP_H);   // V street 2
  g.fillRect(1240, 0,   90, MAP_H);   // V street 3

  // Road dashes
  g.fillStyle(0xffff44, 0.1);
  for (let x = 0; x < MAP_W; x += 70) {
    g.fillRect(x, 370, 42, 8);
    g.fillRect(x, 720, 42, 8);
  }
  for (let y = 0; y < MAP_H; y += 70) {
    g.fillRect(438,  y, 8, 42);
    g.fillRect(858,  y, 8, 42);
    g.fillRect(1278, y, 8, 42);
  }

  // Street lamps
  [
    [396, 55], [396, 165], [396, 275], [396, 450], [396, 560],
    [816, 55], [816, 165], [816, 275], [816, 450], [816, 560],
    [1236, 55], [1236, 165], [1236, 275],
  ].forEach(([lx, ly]) => drawLamp(g, lx, ly));

  // Trees
  [
    [448, 30], [448, 110], [448, 210], [448, 300],
    [478, 70], [478, 180],
    [868, 30], [868, 120], [868, 240], [868, 300],
    [1288, 40], [1288, 150], [1288, 260],
    [448, 440], [448, 550], [868, 440], [868, 540], [1288, 440],
  ].forEach(([tx, ty]) => drawTree(g, tx, ty));

  // ─── Buildings ───
  drawShop(g);

  // Block 2 (x 490–820)
  drawBuilding(g, 510,  60,  180, 140, 0x36455a, 0x243040);
  drawBuilding(g, 700,  80,  100, 120, 0x453660, 0x30244a);
  drawBuilding(g, 520,  450, 170, 130, 0x553636, 0x402424);

  // Block 3 (x 910–1240)
  drawBuilding(g, 930,  55,  200, 150, 0x364536, 0x243024);
  drawBuilding(g, 1120, 75,  100, 110, 0x554036, 0x402a24);
  drawBuilding(g, 950,  445, 150, 140, 0x363655, 0x242440);

  // Block 4 (x 1330–1800) — delivery house is here
  drawBuilding(g, 1540, 55,  180, 150, 0x4a4035, 0x35302a);
  drawBuilding(g, 1740, 70,  130, 120, 0x354540, 0x24302c);
  drawBuilding(g, 1350, 450, 190, 130, 0x404550, 0x2c303a);

  drawDeliveryHouse(g, 1350, 55, 160, 150);

  // Block 1 lower (x 0–400)
  drawBuilding(g, 50,  440, 170, 130, 0x36365a, 0x242440);
}

function addMapLabels(scene) {
  scene.add.text(SHOP.x + SHOP.w / 2, SHOP.y - 16, 'PIZZA PANIC', {
    fontFamily: 'monospace',
    fontSize: '10px',
    color: '#ffffff',
    backgroundColor: '#bb1100',
    padding: { x: 6, y: 3 },
  }).setOrigin(0.5, 1).setDepth(5);

  scene.add.text(1430, 38, '★ DELIVER HERE', {
    fontFamily: 'monospace',
    fontSize: '10px',
    color: '#ffff55',
    backgroundColor: '#00000099',
    padding: { x: 4, y: 2 },
  }).setOrigin(0.5, 1).setDepth(5);
}

// ─── Drawing Helpers ──────────────────────────────────────────────────────────

function drawShop(g) {
  const { x, y, w, h, doorX, doorW } = SHOP;

  // Interior floor
  g.fillStyle(0x3a1e08, 1);
  g.fillRect(x, y, w, h);

  // Floor tiles
  g.fillStyle(0x472510, 1);
  for (let tx = x + 2; tx < x + w - 2; tx += 26) {
    for (let ty = y + 14; ty < y + h - 10; ty += 26) {
      g.fillRect(tx, ty, 24, 24);
    }
  }

  // Kitchen counter (back wall)
  g.fillStyle(0x7a5a20, 1);
  g.fillRect(x + 8, y + 20, w - 16, 24);

  // Oven
  g.fillStyle(0x404040, 1);
  g.fillRect(x + 62, y + 16, 72, 32);
  g.fillStyle(0xff7700, 0.55);
  g.fillRect(x + 66, y + 20, 64, 24);
  g.fillStyle(0x111111, 1);
  g.fillRect(x + 68, y + 22, 60, 20);
  g.fillStyle(0xff9933, 0.35);
  g.fillRect(x + 70, y + 24, 56, 16);

  // Prep table
  g.fillStyle(0xb08830, 1);
  g.fillRect(x + 14, y + 72, w - 28, 26);
  g.fillStyle(0x806418, 1);
  g.fillRect(x + 14, y + 72, w - 28, 4);

  // Shelves on side walls
  g.fillStyle(0x6b4420, 1);
  g.fillRect(x + 12, y + 120, 44, 12);
  g.fillRect(x + w - 56, y + 120, 44, 12);

  // Outer walls
  g.fillStyle(0x9a7050, 1);
  g.fillRect(x,         y,         w,              10); // top
  g.fillRect(x,         y,         10,             h);  // left
  g.fillRect(x + w - 10, y,        10,             h);  // right
  g.fillRect(x,         y + h - 10, doorX - x,     10); // bottom-left
  g.fillRect(doorX + doorW, y + h - 10, x + w - doorX - doorW, 10); // bottom-right

  // Door frame
  g.fillStyle(0xc89060, 1);
  g.fillRect(doorX - 5,    y + h - 48, 5,          48);
  g.fillRect(doorX + doorW, y + h - 48, 5,         48);
  g.fillRect(doorX - 5,    y + h - 48, doorW + 10, 6);

  // Door shadow interior
  g.fillStyle(0x080300, 1);
  g.fillRect(doorX, y + h - 42, doorW, 32);

  // Windows — warm glow
  g.fillStyle(0xffcc44, 0.8);
  g.fillRect(x + 14,      y + 28, 40, 32);
  g.fillRect(x + w - 54,  y + 28, 40, 32);

  // Window panes
  g.fillStyle(0x000000, 0.2);
  g.fillRect(x + 14 + 18,     y + 28,      3, 32);
  g.fillRect(x + 14,          y + 28 + 14, 40, 3);
  g.fillRect(x + w - 54 + 18, y + 28,      3, 32);
  g.fillRect(x + w - 54,      y + 28 + 14, 40, 3);

  // Window warm halo (visible from outside)
  g.fillStyle(0xffaa22, 0.07);
  g.fillCircle(x + 34,      y + 44, 48);
  g.fillCircle(x + w - 34,  y + 44, 48);
}

function drawBuilding(g, x, y, w, h, wallColor, roofColor) {
  g.fillStyle(wallColor, 1);
  g.fillRect(x, y, w, h);
  g.fillStyle(roofColor, 1);
  g.fillRect(x, y, w, 12);
  // Door
  g.fillStyle(0x180f06, 1);
  g.fillRect(x + w / 2 - 12, y + h - 36, 24, 36);
  // Windows
  g.fillStyle(0x334455, 0.45);
  g.fillRect(x + 12, y + 20, 32, 24);
  if (w > 130) g.fillRect(x + w - 44, y + 20, 32, 24);
}

function drawDeliveryHouse(g, x, y, w, h) {
  g.fillStyle(0x48453a, 1);
  g.fillRect(x, y, w, h);
  g.fillStyle(0x323028, 1);
  g.fillRect(x, y, w, 12);
  // Glowing door (delivery target cue)
  g.fillStyle(0xffdd00, 0.65);
  g.fillRect(x + w / 2 - 15, y + h - 44, 30, 44);
  g.fillStyle(0x180f00, 1);
  g.fillRect(x + w / 2 - 12, y + h - 41, 24, 41);
  // Door glow spill onto step
  g.fillStyle(0xffee55, 0.3);
  g.fillRect(x + w / 2 - 22, y + h, 44, 14);
  // Windows
  g.fillStyle(0x88aacc, 0.35);
  g.fillRect(x + 14, y + 22, 34, 26);
  g.fillRect(x + w - 48, y + 22, 34, 26);
}

function drawTree(g, x, y) {
  // Trunk
  g.fillStyle(0x281608, 1);
  g.fillRect(x - 3, y + 10, 6, 18);
  // Canopy
  g.fillStyle(0x183020, 1);
  g.fillCircle(x, y, 16);
  g.fillStyle(0x1c3e26, 0.9);
  g.fillCircle(x - 6, y - 4, 10);
  g.fillCircle(x + 5, y - 3, 10);
}

function drawLamp(g, x, y) {
  // Pole
  g.fillStyle(0x48485a, 1);
  g.fillRect(x - 2, y + 8, 4, 28);
  // Head
  g.fillStyle(0xfff0aa, 0.9);
  g.fillCircle(x, y + 8, 6);
  // Glow halo
  g.fillStyle(0xffe066, 0.1);
  g.fillCircle(x, y + 8, 30);
}

// ─── Physics Walls ────────────────────────────────────────────────────────────

function buildShopWalls(scene) {
  const { x, y, w, h, doorX, doorW } = SHOP;
  const T = 10;
  addWall(scene, x,             y,         w,                     T); // top
  addWall(scene, x,             y,         T,                     h); // left
  addWall(scene, x + w - T,     y,         T,                     h); // right
  addWall(scene, x,             y + h - T, doorX - x,             T); // bottom-left
  addWall(scene, doorX + doorW, y + h - T, x + w - doorX - doorW, T); // bottom-right
}

function buildEnvColliders(scene) {
  [
    // Block 2
    [510,  60,  180, 140],
    [700,  80,  100, 120],
    [520,  450, 170, 130],
    // Block 3
    [930,  55,  200, 150],
    [1120, 75,  100, 110],
    [950,  445, 150, 140],
    // Block 4
    [1350, 55,  160, 150], // delivery house
    [1540, 55,  180, 150],
    [1740, 70,  130, 120],
    [1350, 450, 190, 130],
    // Block 1 lower
    [50,   440, 170, 130],
  ].forEach(([x, y, w, h]) => addWall(scene, x, y, w, h));
}

function addWall(scene, x, y, w, h) {
  const r = scene.add.rectangle(x + w / 2, y + h / 2, w, h, 0, 0);
  walls.add(r);
  r.refreshBody();
}
