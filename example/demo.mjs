/**
 * Generates a realistic demo recording for PhoenixReplay.
 *
 * Run against the dev server:
 *   cd example && mix ecto.reset && mix phx.server &
 *   npx playwright test demo.mjs
 *
 * Or directly:
 *   bunx playwright test demo.mjs
 *
 * Then open http://localhost:4005/replay to watch the replay.
 */
import { test, expect } from "@playwright/test";

const BASE = "http://localhost:4005";

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function humanType(locator, text, { delay = 80, jitter = 40 } = {}) {
  for (const char of text) {
    await locator.pressSequentially(char, {
      delay: delay + Math.random() * jitter - jitter / 2,
    });
  }
}

async function humanBackspace(locator, count, { delay = 50 } = {}) {
  for (let i = 0; i < count; i++) {
    await locator.press("Backspace");
    await sleep(delay + Math.random() * 30);
  }
}

test("generate demo recording", async ({ page }) => {
  test.setTimeout(60_000);

  await page.goto(BASE);
  await expect(page.locator("h1")).toHaveText("Tasks");
  await sleep(1200);

  // --- Seed: create first task quickly via UI ---
  await page.getByRole("link", { name: "New Task" }).click();
  await expect(page.getByRole("heading", { name: "New Task" })).toBeVisible();
  await sleep(500);

  const title = page.locator("#title");
  const description = page.locator("#description");
  const priority = page.locator("#priority");

  await humanType(title, "Set up CI pipeline");
  await sleep(300);
  await humanType(description, "GitHub Actions for tests and deploys");
  await sleep(200);
  await priority.selectOption("high");
  await sleep(200);
  await page.getByRole("button", { name: "Create Task" }).click();
  await expect(page.getByText("Set up CI pipeline")).toBeVisible();
  await sleep(800);

  // --- Second task: quick one ---
  await page.getByRole("link", { name: "New Task" }).click();
  await sleep(400);
  await humanType(title, "Update README");
  await sleep(200);
  await page.getByRole("button", { name: "Create Task" }).click();
  await expect(page.getByText("Update README")).toBeVisible();
  await sleep(600);

  // --- Third task: type with typo and correct it ---
  await page.getByRole("link", { name: "New Task" }).click();
  await expect(page.getByRole("heading", { name: "New Task" })).toBeVisible();
  await sleep(600);

  // Type "Refactr" (typo), pause, backspace 2 chars, retype "tor auth module"
  await humanType(title, "Refactr", { delay: 95 });
  await sleep(700);
  await humanBackspace(title, 2);
  await sleep(300);
  await humanType(title, "tor auth module", { delay: 70 });
  await sleep(400);

  // Description with a pause mid-sentence (thinking...)
  await humanType(description, "Extract the auth logic into ", { delay: 65 });
  await sleep(1100);
  await humanType(description, "a plug + context module", { delay: 55 });
  await sleep(300);
  await priority.selectOption("medium");
  await sleep(300);
  await page.getByRole("button", { name: "Create Task" }).click();
  await expect(page.getByText("Refactor auth module")).toBeVisible();
  await sleep(800);

  // --- Browse filters ---
  await page.getByRole("button", { name: /Active \d/ }).click();
  await sleep(900);
  await page.getByRole("button", { name: /All \d/ }).click();
  await sleep(500);

  // --- Toggle completion ---
  await page
    .getByRole("button", { name: "Toggle Update README" })
    .click();
  await sleep(600);
  await page.getByRole("button", { name: /Completed \d/ }).click();
  await sleep(700);
  await page.getByRole("button", { name: /All \d/ }).click();
  await sleep(500);

  // --- Edit a task: slow backspace then retype ---
  await page.getByRole("link", { name: "Edit Update README" }).click();
  await expect(
    page.getByRole("heading", { name: "Edit Task" })
  ).toBeVisible();
  await sleep(500);

  // Move to end then backspace "README" (6 chars)
  await title.press("End");
  await sleep(100);
  await humanBackspace(title, 6, { delay: 60 });
  await sleep(400);
  await humanType(title, "docs and README", { delay: 70 });
  await sleep(300);
  await humanType(description, "Add install guide and API docs");
  await sleep(200);
  await page.getByRole("button", { name: "Save Changes" }).click();
  await expect(page.getByText("Update docs and README")).toBeVisible();
  await sleep(600);

  // --- Delete a task ---
  await page
    .getByRole("button", { name: "Delete Set up CI pipeline" })
    .click();
  await sleep(500);

  // --- Final state check ---
  await expect(page.getByRole("button", { name: /All \d/ })).toContainText(
    "2"
  );
  await sleep(800);

  // Navigate away to finalize the recording
  await page.goto(`${BASE}/replay`);
  await expect(page.locator("h1")).toContainText("PhoenixReplay");
  await expect(
    page.getByText("ExampleWeb.TaskLive.Index").first()
  ).toBeVisible();
});
