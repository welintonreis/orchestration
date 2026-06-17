import { createConsumer } from "@rails/actioncable"

// One WebSocket per browser tab, shared by every Stimulus controller that
// subscribes to a channel. Each controller previously called
// createConsumer() itself, opening its own socket — on a page with many
// running containers (stats_controller per row) that meant one connection
// per row, storming Puma with simultaneous upgrades on every page load.
export default createConsumer()
