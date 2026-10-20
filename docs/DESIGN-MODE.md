# Developer-side layout customization

Bonsai has no end-user Design mode, editor menu, or editing panel. Layout customization is a separate workspace tool compiled with `BONSAI_DESIGN_EDITOR`. The installed Bonsai is unchanged.

## Open the developer preview

Run `bash scripts/design-studio.sh`, then open **work/Bonsai Design Studio.app**. This previews Bonsai's actual SwiftUI/AppKit components with a separate bundle identifier and preferences domain. No OpenDesign HTML import is required.

1. Choose a scene in the preview's **Scenes** menu, then select **Edit layout** in its developer toolbar.
2. Select an element from the inspector's grouped list, or use **Select on page** and click an outlined element. On the standard page previews, another page's target opens that page; Settings targets open the Settings preview.
3. Adjust size/text size, width/height scale, space around, and horizontal/vertical position. Minus/plus controls adjust one percent or one point. Repeated rows share a style.
4. Turn **Pick elements on screen** off to hide outlines, or choose **Done**. The canvas is a design preview; operational controls are not clickable.
5. Click **Save build settings** to export the current styles into **Resources/InterfaceDesign.json** in this workspace. Regular builds bundle that file. Run `bash scripts/build.sh release` when ready to build the customized app; installation remains a separate step.

The preview saves its working edits locally across launches. Undo retains 60 recent changes in the current session. Reset element/all restores original geometry; export again to apply the reset to regular builds. Closing without export keeps edits in the preview only.

The 43 styles include the five main navigation buttons and spacing; page trees, headings and main actions; Analyze's sidebar tree and folder rows; Cleanup categories; Apps tabs and Uninstall/Updates/Startup row styles; Settings title/tabs/rows; and Status cards/tree/process rows. State-specific elements become visible in their landing/review/map scenes. Use Scenes first when changing to/from the dedicated Updates demo. Choosing a target does not discard an existing scan or run maintenance.

Width/height are scale factors, not absolute frame sizes. Flexible cards and rows still fit the available viewport. Position changes keep the pick outline attached. The navigation selection animation uses the tuned button dimensions. Source names are stable keys such as `clean.tree`, `apps.tabs` and `status.CPU`.

Example compiled style:

```json
{
  "clean.tree": {"scale": 0.9, "width": 1, "height": 1, "spacing": 0, "x": 0, "y": -8}
}
```

Regular builds read only this bundled configuration, validate finite bounds/known targets and ignore preview-session preferences. Their executable excludes the inspector, picking surface and preview surface. Default `{}` leaves the approved appearance unchanged.

OpenDesign's documented editor works with HTML prototypes and exports; it does not provide a documented direct editing workflow for this SwiftUI project. This workspace tool edits the actual native layout. Reference: [OpenDesign README](https://github.com/nexu-io/open-design/blob/main/README.md).
