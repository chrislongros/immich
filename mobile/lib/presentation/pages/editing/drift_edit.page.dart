import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:crop_image/crop_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/asset_edit.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/utils/editor.utils.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:openapi/api.dart' show CropParameters, RotateParameters;

/// A stateful widget that provides functionality for editing an image.
///
/// This widget allows users to edit an image provided either as an [Asset] or
/// directly as an [Image]. It ensures that exactly one of these is provided.
///
/// It also includes a conversion method to convert an [Image] to a [Uint8List] to save the image on the user's phone
/// They automatically navigate to the [HomePage] with the edited image saved and they eventually get backed up to the server.
@RoutePage()
class DriftEditImagePage extends ConsumerStatefulWidget {
  final Image image;
  final BaseAsset asset;
  final List<AssetEdit> edits;
  final ExifInfo exifInfo;

  const DriftEditImagePage({
    super.key,
    required this.image,
    required this.asset,
    required this.edits,
    required this.exifInfo,
  });

  @override
  ConsumerState<DriftEditImagePage> createState() => _DriftEditImagePageState();
}

class _DriftEditImagePageState extends ConsumerState<DriftEditImagePage> {
  late final CropController cropController;
  double? aspectRatio;

  late final originalWidth = widget.exifInfo.isFlipped ? widget.exifInfo.height : widget.exifInfo.width;
  late final originalHeight = widget.exifInfo.isFlipped ? widget.exifInfo.width : widget.exifInfo.height;

  bool isEditing = false;

  (Rect, CropRotation) getInitialEditorState() {
    final existingCrop = widget.edits.firstWhereOrNull((edit) => edit.action == AssetEditAction.crop);

    Rect crop = existingCrop != null
        ? convertCropParametersToRect(
            CropParameters.fromJson(existingCrop.parameters)!,
            originalWidth ?? 0,
            originalHeight ?? 0,
          )
        : const Rect.fromLTRB(0, 0, 1, 1);

    final existingRotationParameters = RotateParameters.fromJson(
      widget.edits.firstWhereOrNull((edit) => edit.action == AssetEditAction.rotate)?.parameters,
    );

    final existingRotationAngle =
        CropRotationExtension.fromDegrees(existingRotationParameters?.angle.toInt() ?? 0) ?? CropRotation.up;

    crop = convertCropRectToRotated(crop, existingRotationAngle);
    return (crop, existingRotationAngle);
  }

  Future<void> _saveEditedImage() async {
    setState(() {
      isEditing = true;
    });

    CropRotation rotation = cropController.rotation;
    Rect cropRect = convertCropRectFromRotated(cropController.crop, rotation);
    final cropParameters = convertRectToCropParameters(cropRect, originalWidth ?? 0, originalHeight ?? 0);

    final edits = <AssetEdit>[];

    if (cropParameters.width != originalWidth || cropParameters.height != originalHeight) {
      edits.add(AssetEdit(action: AssetEditAction.crop, parameters: cropParameters.toJson()));
    }

    if (rotation != CropRotation.up) {
      edits.add(
        AssetEdit(
          action: AssetEditAction.rotate,
          parameters: RotateParameters(angle: rotation.degrees).toJson(),
        ),
      );
    }

    try {
      final completer = ref.read(websocketProvider.notifier).waitForEvent("AssetEditReadyV1", (dynamic data) {
        final eventData = data as Map<String, dynamic>;
        return eventData["asset"]['id'] == widget.asset.remoteId;
      }, const Duration(seconds: 10));

      await ref.read(actionProvider.notifier).applyEdits(ActionSource.viewer, edits);
      await completer;

      ImmichToast.show(context: context, msg: 'asset_edit_success'.tr(), toastType: ToastType.success);

      context.pop();
    } catch (e) {
      // show error snackbar
      if (mounted) {
        ImmichToast.show(context: context, msg: 'asset_edit_failed'.tr(), toastType: ToastType.error);
      }
      return;
    } finally {
      setState(() {
        isEditing = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    final (existingCrop, existingRotationAngle) = getInitialEditorState();
    cropController = CropController(defaultCrop: existingCrop, rotation: existingRotationAngle);
  }

  @override
  void dispose() {
    cropController.dispose();
    super.dispose();
  }

  Widget _buildProgressIndicator() {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.scaffoldBackgroundColor,
        title: Text("edit".tr()),
        leading: const ImmichCloseButton(),
        actions: [
          isEditing
              ? _buildProgressIndicator()
              : ImmichIconButton(
                  icon: Icons.done_rounded,
                  color: ImmichColor.primary,
                  variant: ImmichVariant.ghost,
                  onPressed: _saveEditedImage,
                ),
        ],
      ),
      backgroundColor: context.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.only(top: 20),
                  width: constraints.maxWidth * 0.9,
                  height: constraints.maxHeight * 0.6,
                  child: CropImage(controller: cropController, image: widget.image, gridColor: Colors.white),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ImmichIconButton(
                                  icon: Icons.rotate_left,
                                  variant: ImmichVariant.ghost,
                                  color: ImmichColor.secondary,
                                  onPressed: () => cropController.rotateLeft(),
                                ),
                                ImmichIconButton(
                                  icon: Icons.rotate_right,
                                  variant: ImmichVariant.ghost,
                                  color: ImmichColor.secondary,
                                  onPressed: () => cropController.rotateRight(),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: <Widget>[
                              _AspectRatioButton(
                                cropController: cropController,
                                currentAspectRatio: aspectRatio,
                                ratio: null,
                                label: 'Free',
                                onPressed: () {
                                  setState(() {
                                    cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                    aspectRatio = null;
                                    cropController.aspectRatio = null;
                                  });
                                },
                              ),
                              _AspectRatioButton(
                                cropController: cropController,
                                currentAspectRatio: aspectRatio,
                                ratio: 1.0,
                                label: '1:1',
                                onPressed: () {
                                  setState(() {
                                    cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                    aspectRatio = 1.0;
                                    cropController.aspectRatio = 1.0;
                                  });
                                },
                              ),
                              _AspectRatioButton(
                                cropController: cropController,
                                currentAspectRatio: aspectRatio,
                                ratio: 16.0 / 9.0,
                                label: '16:9',
                                onPressed: () {
                                  setState(() {
                                    cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                    aspectRatio = 16.0 / 9.0;
                                    cropController.aspectRatio = 16.0 / 9.0;
                                  });
                                },
                              ),
                              _AspectRatioButton(
                                cropController: cropController,
                                currentAspectRatio: aspectRatio,
                                ratio: 3.0 / 2.0,
                                label: '3:2',
                                onPressed: () {
                                  setState(() {
                                    cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                    aspectRatio = 3.0 / 2.0;
                                    cropController.aspectRatio = 3.0 / 2.0;
                                  });
                                },
                              ),
                              _AspectRatioButton(
                                cropController: cropController,
                                currentAspectRatio: aspectRatio,
                                ratio: 7.0 / 5.0,
                                label: '7:5',
                                onPressed: () {
                                  setState(() {
                                    cropController.crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                                    aspectRatio = 7.0 / 5.0;
                                    cropController.aspectRatio = 7.0 / 5.0;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AspectRatioButton extends StatelessWidget {
  final CropController cropController;
  final double? currentAspectRatio;
  final double? ratio;
  final String label;
  final VoidCallback onPressed;

  const _AspectRatioButton({
    required this.cropController,
    required this.currentAspectRatio,
    required this.ratio,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(switch (label) {
            'Free' => Icons.crop_free_rounded,
            '1:1' => Icons.crop_square_rounded,
            '16:9' => Icons.crop_16_9_rounded,
            '3:2' => Icons.crop_3_2_rounded,
            '7:5' => Icons.crop_7_5_rounded,
            _ => Icons.crop_free_rounded,
          }, color: currentAspectRatio == ratio ? context.primaryColor : context.themeData.iconTheme.color),
          onPressed: onPressed,
        ),
        Text(label, style: context.textTheme.displayMedium),
      ],
    );
  }
}
