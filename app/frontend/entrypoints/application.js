// Allure — JavaScript entry point.
//
// Turbo Drive is on. That is a deliberate choice with a consequence: nothing in
// this app may bind behaviour on `DOMContentLoaded`, because Turbo only fires it
// on the very first load. Anything that touches the DOM belongs in a Stimulus
// controller, which gets connect/disconnect for free on every navigation.

import "../styles/application.scss";

import "@hotwired/turbo-rails";
import { Application } from "@hotwired/stimulus";
import { registerControllers } from "stimulus-vite-helpers";

import * as bootstrap from "@tabler/core/dist/js/tabler.esm.min.js";

// Tabler's own JS expects a global, and so do the data-bs-* attributes used
// throughout its markup.
window.bootstrap = bootstrap;

const application = Application.start();
application.debug = import.meta.env.DEV;
window.Stimulus = application;

const controllers = import.meta.glob("../controllers/**/*_controller.js", { eager: true });
registerControllers(application, controllers);
