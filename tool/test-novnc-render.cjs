#!/usr/bin/env node
"use strict";

const { chromium } = require("playwright");
const { execFileSync } = require("node:child_process");

const display = process.env.DISPLAY || ":100";
const url = process.env.MICROOS_NOVNC_URL ||
  "http://127.0.0.1:6081/vnc.html?autoconnect=1&resize=scale&path=websockify&quality=6&compression=2";
let websocketOpened = false;
let websocketFrames = 0;

function log(message) {
  const line = "[novnc-e2e] " + message;
  process.stdout.write(line + "\n");
}

function setDesktopColor(color) {
  execFileSync("xsetroot", ["-display", display, "-solid", color], {
    stdio: "pipe",
    timeout: 5000,
  });
}

async function main() {
  let browser;
  let page;
  try {
    setDesktopColor("#123456");
    browser = await chromium.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-dev-shm-usage"],
    });
    page = await browser.newPage({ viewport: { width: 1000, height: 700 } });
    page.on("console", (message) => log("browser console " + message.type() + ": " + message.text()));
    page.on("pageerror", (error) => log("browser pageerror: " + (error.stack || error.message)));
    page.on("requestfailed", (request) => log("request failed: " + request.url() + " " + (request.failure()?.errorText || "")));
    page.on("websocket", (socket) => {
      log("WebSocket created: " + socket.url());
      socket.on("open", () => {
        websocketOpened = true;
        log("WebSocket OPEN");
      });
      socket.on("socketerror", (error) => log("WebSocket ERROR: " + error));
      socket.on("close", () => log("WebSocket CLOSED"));
      socket.on("framereceived", () => { websocketFrames += 1; });
    });

    log("opening " + url);
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 20000 });
    await page.waitForSelector("#noVNC_canvas", { timeout: 15000 });

    const sample = async () => page.evaluate(() => {
      const canvas = document.getElementById("noVNC_canvas");
      if (!canvas || canvas.width < 2 || canvas.height < 2) {
        return { exists: !!canvas, width: canvas?.width || 0, height: canvas?.height || 0 };
      }
      try {
        const pixel = canvas.getContext("2d").getImageData(
          Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1
        ).data;
        return {
          exists: true,
          width: canvas.width,
          height: canvas.height,
          pixel: [pixel[0], pixel[1], pixel[2], pixel[3]],
          rfbState: window.UI?.rfb?._rfbConnectionState || "unavailable",
        };
      } catch (error) {
        return { exists: true, width: canvas.width, height: canvas.height, error: String(error) };
      }
    });

    const first = await page.waitForFunction((target) => {
      const canvas = document.getElementById("noVNC_canvas");
      if (!canvas || canvas.width < 2 || canvas.height < 2) return false;
      try {
        const p = canvas.getContext("2d").getImageData(
          Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1
        ).data;
        return Math.abs(p[0] - target[0]) < 8 &&
          Math.abs(p[1] - target[1]) < 8 &&
          Math.abs(p[2] - target[2]) < 8;
      } catch (_) { return false; }
    }, [18, 52, 86], { timeout: 25000 }).then(() => sample());

    log("first framebuffer color rendered: " + JSON.stringify(first));
    if (first.error) throw new Error("noVNC canvas read failed: " + first.error);

    setDesktopColor("#d14b2a");
    const second = await page.waitForFunction((target) => {
      const canvas = document.getElementById("noVNC_canvas");
      if (!canvas || canvas.width < 2 || canvas.height < 2) return false;
      try {
        const p = canvas.getContext("2d").getImageData(
          Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1
        ).data;
        return Math.abs(p[0] - target[0]) < 8 &&
          Math.abs(p[1] - target[1]) < 8 &&
          Math.abs(p[2] - target[2]) < 8;
      } catch (_) { return false; }
    }, [209, 75, 42], { timeout: 15000 }).then(() => sample());

    log("changed framebuffer color rendered: " + JSON.stringify(second));
    if (!websocketOpened) log("NOTE: Playwright did not emit a WebSocket open event; pixel assertions passed");
    log("WebSocket frames received by browser: " + websocketFrames);
    if (websocketFrames < 1) throw new Error("WebSocket carried no received frames");
    await page.screenshot({ path: "/tmp/microos-novnc-render.png" });
    log("PASS: noVNC rendered two distinct X11 framebuffer colors");
  } catch (error) {
    log("FAIL: " + (error.stack || error.message));
    if (page) {
      try {
        const state = await page.evaluate(() => {
          const c = document.getElementById("noVNC_canvas");
          return {
            exists: !!c,
            width: c?.width || 0,
            height: c?.height || 0,
            status: document.querySelector("#noVNC_status")?.textContent || "",
            rfbState: window.UI?.rfb?._rfbConnectionState || "unavailable",
          };
        });
        log("final canvas: " + JSON.stringify(state));
        await page.screenshot({ path: "/tmp/microos-novnc-render-failure.png", fullPage: true }).catch(() => {});
      } catch (diagnosticError) {
        log("diagnostic collection failed: " + diagnosticError);
      }
    }
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

main().catch((error) => {
  process.stderr.write("[novnc-e2e] FATAL: " + (error.stack || error.message) + "\n");
  process.exitCode = 1;
});
