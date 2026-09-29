// Import and register all your controllers from the importmap under controllers/*

import { application } from "controllers/application";

// Load a controller only when an element declares it. This keeps page-specific
// code (especially report charts and their D3 dependencies) out of the initial
// download for unrelated pages.
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading";
lazyLoadControllersFrom("controllers", application);
