// Copyright Amazon.com Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
// Do not modify this file. This file is machine generated, and any changes to it will be overwritten.

using System;
using AWS.EncryptionSDK.Core;

namespace AWS.EncryptionSDK.Core
{
    public class GetEncryptionMaterialsOutput
    {
        private AWS.EncryptionSDK.Core.EncryptionMaterials _encryptionMaterials;

        public AWS.EncryptionSDK.Core.EncryptionMaterials EncryptionMaterials
        {
            get { return this._encryptionMaterials; }
            set { this._encryptionMaterials = value; }
        }

        internal bool IsSetEncryptionMaterials()
        {
            return this._encryptionMaterials != null;
        }

        public void Validate()
        {
            if (!IsSetEncryptionMaterials())
                throw new System.ArgumentException("Missing value for required property 'EncryptionMaterials'");
        }
    }
}
