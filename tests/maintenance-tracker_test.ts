import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Can create a new maintenance request",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("HVAC System Repair"),
        types.ascii("Air conditioning unit not working in building A"),
        types.ascii("Building A - Floor 2"),
        types.ascii("high"),
        types.uint(500)
      ], deployer.address)
    ]);
    
    assertEquals(block.receipts.length, 1);
    assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
  },
});

Clarinet.test({
  name: "Can retrieve request details",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    
    // Create request first
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Plumbing Issue"),
        types.ascii("Sink leaking in kitchen"),
        types.ascii("Kitchen - Main Floor"),
        types.ascii("medium"),
        types.uint(200)
      ], deployer.address)
    ]);
    
    // Get request details
    let getRequest = chain.callReadOnlyFn(
      "maintenance-tracker",
      "get-request",
      [types.uint(1)],
      deployer.address
    );
    
    const request = getRequest.result.expectSome().expectTuple();
    assertEquals(request["title"], types.ascii("Plumbing Issue"));
    assertEquals(request["priority"], types.ascii("medium"));
    assertEquals(request["status"], types.ascii("pending"));
    assertEquals(request["estimated-cost"], types.uint(200));
  },
});

Clarinet.test({
  name: "Can assign technician to request",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const technician = accounts.get("wallet_1")!;
    
    // Create request
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Electrical Issue"),
        types.ascii("Lights flickering in office"),
        types.ascii("Office Block C"),
        types.ascii("critical"),
        types.uint(300)
      ], deployer.address)
    ]);
    
    // Assign technician
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "assign-technician", [
        types.uint(1),
        types.principal(technician.address)
      ], deployer.address)
    ]);
    
    assertEquals(block.receipts[0].result.expectOk(), types.bool(true));
    
    // Verify assignment
    let getRequest = chain.callReadOnlyFn(
      "maintenance-tracker",
      "get-request",
      [types.uint(1)],
      deployer.address
    );
    
    const request = getRequest.result.expectSome().expectTuple();
    assertEquals(request["assigned-to"], types.some(types.principal(technician.address)));
    assertEquals(request["status"], types.ascii("in-progress"));
  },
});

Clarinet.test({
  name: "Can update request status",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const technician = accounts.get("wallet_1")!;
    
    // Create and assign request
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Door Repair"),
        types.ascii("Door handle broken"),
        types.ascii("Room 101"),
        types.ascii("low"),
        types.uint(100)
      ], deployer.address),
      Tx.contractCall("maintenance-tracker", "assign-technician", [
        types.uint(1),
        types.principal(technician.address)
      ], deployer.address)
    ]);
    
    // Update status to completed
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "update-status", [
        types.uint(1),
        types.ascii("completed"),
        types.some(types.ascii("Door handle replaced successfully"))
      ], technician.address)
    ]);
    
    assertEquals(block.receipts[0].result.expectOk(), types.bool(true));
    
    // Verify status update
    let getRequest = chain.callReadOnlyFn(
      "maintenance-tracker",
      "get-request",
      [types.uint(1)],
      deployer.address
    );
    
    const request = getRequest.result.expectSome().expectTuple();
    assertEquals(request["status"], types.ascii("completed"));
    assertEquals(request["completion-notes"], types.some(types.ascii("Door handle replaced successfully")));
  },
});

Clarinet.test({
  name: "Can update actual cost",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const technician = accounts.get("wallet_1")!;
    
    // Create and assign request
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Window Repair"),
        types.ascii("Cracked window glass"),
        types.ascii("Conference Room"),
        types.ascii("medium"),
        types.uint(150)
      ], deployer.address),
      Tx.contractCall("maintenance-tracker", "assign-technician", [
        types.uint(1),
        types.principal(technician.address)
      ], deployer.address)
    ]);
    
    // Update actual cost
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "update-actual-cost", [
        types.uint(1),
        types.uint(175)
      ], technician.address)
    ]);
    
    assertEquals(block.receipts[0].result.expectOk(), types.bool(true));
    
    // Verify cost update
    let getRequest = chain.callReadOnlyFn(
      "maintenance-tracker",
      "get-request",
      [types.uint(1)],
      deployer.address
    );
    
    const request = getRequest.result.expectSome().expectTuple();
    assertEquals(request["actual-cost"], types.some(types.uint(175)));
  },
});

Clarinet.test({
  name: "Analytics track requests correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const technician = accounts.get("wallet_1")!;
    
    // Create multiple requests
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Request 1"),
        types.ascii("Description 1"),
        types.ascii("Location 1"),
        types.ascii("high"),
        types.uint(100)
      ], deployer.address),
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Request 2"),
        types.ascii("Description 2"),
        types.ascii("Location 2"),
        types.ascii("medium"),
        types.uint(200)
      ], deployer.address)
    ]);
    
    // Assign one request
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "assign-technician", [
        types.uint(1),
        types.principal(technician.address)
      ], deployer.address)
    ]);
    
    // Complete one request
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "update-status", [
        types.uint(1),
        types.ascii("completed"),
        types.none()
      ], technician.address)
    ]);
    
    // Check analytics
    let analytics = chain.callReadOnlyFn(
      "maintenance-tracker",
      "get-analytics",
      [],
      deployer.address
    );
    
    const data = analytics.result.expectTuple();
    assertEquals(data["total-requests"], types.uint(2));
    assertEquals(data["pending"], types.uint(1));
    assertEquals(data["in-progress"], types.uint(0));
    assertEquals(data["completed"], types.uint(1));
    assertEquals(data["cancelled"], types.uint(0));
  },
});

Clarinet.test({
  name: "Prevents unauthorized actions",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const unauthorized = accounts.get("wallet_1")!;
    
    // Create request
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Test Request"),
        types.ascii("Test Description"),
        types.ascii("Test Location"),
        types.ascii("low"),
        types.uint(50)
      ], deployer.address)
    ]);
    
    // Try to assign technician as unauthorized user
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "assign-technician", [
        types.uint(1),
        types.principal(unauthorized.address)
      ], unauthorized.address)
    ]);
    
    assertEquals(block.receipts[0].result.expectErr(), types.uint(100)); // ERR-NOT-AUTHORIZED
  },
});

Clarinet.test({
  name: "Validates input parameters",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    
    // Try to create request with invalid priority
    let block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Test Request"),
        types.ascii("Test Description"),
        types.ascii("Test Location"),
        types.ascii("invalid"),  // Invalid priority
        types.uint(100)
      ], deployer.address)
    ]);
    
    assertEquals(block.receipts[0].result.expectErr(), types.uint(103)); // ERR-INVALID-PRIORITY
    
    // Try to create request with zero cost
    block = chain.mineBlock([
      Tx.contractCall("maintenance-tracker", "create-request", [
        types.ascii("Test Request"),
        types.ascii("Test Description"),
        types.ascii("Test Location"),
        types.ascii("medium"),
        types.uint(0)  // Invalid cost
      ], deployer.address)
    ]);
    
    assertEquals(block.receipts[0].result.expectErr(), types.uint(105)); // ERR-INVALID-COST
  },
});
