# Glance for the Mac App Store

## English (U.S.) listing draft

| Field | Copy |
| --- | --- |
| Name | Glance |
| Subtitle | Compare images and copy text |
| Keywords | photo,viewer,preview,video,ocr,screenshot,folder,reference,clipboard,zoom |
| Promotional text | Compare two edits side by side, copy a line of text from a screenshot, or browse the photos and videos in a folder. |

**Description**

Open a folder of photos and videos in Glance. Move through the files, zoom in on a detail, or bring two images together to see what changed between edits.

Copy text straight from an image. Grab a line from a screenshot and paste it into the document you’re working on.

Browsing, comparing images, and recognizing text happen on your Mac. When you choose a cloud Widget, Glance sends the selected media and task settings for processing. Cloud Widgets can use credits. Glance Pro and credit packs are available through in-app purchase.

## Simplified Chinese listing draft

| 字段 | 文案 |
| --- | --- |
| 名称 | Glance |
| 副标题 | 并排对比图片，从截图中复制文字 |
| 关键词 | 看图,照片,视频,预览,文字识别,文件夹,参考图,剪贴板,放大 |
| 推广文本 | 把原图和修过的照片放在一起看，放大检查细节，或从截图里复制需要的那一行字。 |

**描述**

用 Glance 打开一个文件夹，就能逐个查看里面的照片和视频。挑出两张图片并排对比，看看这次修图改了哪里。

遇到截图里的地址、标题或一段说明，可以直接识别并复制文字，粘贴到正在写的文档里。

浏览文件、对比图片和识别文字都在 Mac 上完成。使用云端 Widget 时，Glance 会上传你选择的媒体和任务参数。部分云端任务会消耗积分。你可以通过 App 内购买解锁 Glance Pro 或购买积分包。

## App Review notes draft

1. Choose File → Open… and select a local image. To browse a folder, choose File → Open Folder… and select a folder containing a few images. Glance uses the macOS folder picker to request access. Glance → Grant Folder Access… lets you authorize another folder.
2. To try Peek, select a link in a text document and use the default Control–Option–K shortcut. Peek uses Accessibility permission to read the selection in the frontmost app. You can review local files through the File menu if you decline this permission.
3. Choose Glance → Buy Glance Pro… to inspect the available Pro purchases. Use Glance → Restore Purchases with the original account to test restoration. Credit packs are consumables. To test a cloud Widget, sign in, select an image and check the displayed credit cost before running it. The service records the task against the signed-in account.
4. Account deletion is available under Glance → Delete account.

**Before sending these notes:** Verify the steps on the TestFlight build. Supply a working reviewer sign-in method in App Review Information and enough credits for a complete Widget run. If using an email code, verify that the reviewer can receive it independently. Keep credentials in App Store Connect.

## App Privacy draft for the publisher

Proposed answer to data collection: **Yes**. The service retains account, purchase, task and analytics records. Suggested mappings below follow the current [Glance privacy policy source](../../website/static/src/pages/41-privacy.html) and [Apple’s data definitions](https://developer.apple.com/app-store/app-privacy-details/).

| App Store Connect data type | Proposed purposes | Linkage and scope to confirm |
| --- | --- | --- |
| Email Address, Name, User ID | App Functionality | Linked to accounts. Include names supplied through supported identity providers. User ID also applies to signed-in analytics. |
| Device ID | App Functionality, Analytics | A hashed device identifier is used for licensing and analytics and can be associated with an account. |
| Purchases | App Functionality | Linked. The service records the product, Apple transaction and entitlement or credit grant. Review Analytics as an additional purpose for purchase events. |
| Photos or Videos, Other User Content | App Functionality | Linked when submitted to a cloud Widget. Include retained prompts, inputs and results. Review additional media types against the enabled Widget catalog. |
| Product Interaction | Analytics | Events can carry a device identifier or signed-in account ID. |
| Coarse Location | App Functionality | Confirm whether country derived from IP is retained by the service or its processors and whether it is linked. |
| Diagnostics, Customer Support, Other Data Types | Confirm against stored fields | Inspect service logs, diagnostic submissions, device names, identity-provider profile photos and support retention. Map each retained field to the closest Apple category and purpose. |

Proposed tracking answer: **No**, subject to confirming that each integrated partner also follows Apple’s tracking definition. Review the app and its service providers together. The current policy describes Google, email sign-in and website checkout. Update it to cover Sign in with Apple and StoreKit transaction processing before publishing the questionnaire.

## First TestFlight build

- Select the Glance-MAS target’s scheme and archive the Release configuration. Both distribution targets use com.glance.app. A separate macOS user or test Mac can keep the test independent of an existing installation.
- Verify the App Store Connect record, enabled products, provisioning for Sign in with Apple, and sandbox notifications. The service expects migrations 0029 and 0030 and the APP_STORE_ISSUER_ID, APP_STORE_KEY_ID and APP_STORE_PRIVATE_KEY settings. Its notification route is /api/v2/app-store/notifications.
- Test opening a single file, reopening a granted folder after relaunch, Peek with permission granted and declined, Apple sign-in, a sandbox credit purchase, a Pro purchase and restoration. Verify the resulting balance or entitlement after relaunch. Exercise a failed Widget task and confirm the final balance.
- Export compliance is pending the publisher’s confirmation for the shipped app and its dependencies. Both targets share the source Info.plist. Apply any approved store-only declaration in the MAS configuration. [Apple export compliance guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

Listing field reference: [Apple’s platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).
